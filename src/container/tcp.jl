
export TCPProtocol, init, parse_id, acquire_tcp_connection, release_tcp_connection

using Sockets:
    connect,
    write,
    getpeername,
    read,
    listen,
    accept,
    IPAddr,
    TCPSocket,
    TCPServer,
    @ip_str,
    InetAddr

using ConcurrentUtilities: Pool, acquire, release, drain!, ReadWriteLock, readlock, readunlock, lock, unlock

using Dates: Dates
import Base.close

mutable struct AtomicCounter
    @atomic counter::Int
end

"""
Describes a connection pool for tcp connections. It supports 
`keep_alive_time_ms` which specifies the time a connection is kept without usage
before closing the connection.

All methods defined on the pool are thread-safe.
"""
@kwdef mutable struct TCPConnectionPool
    keep_alive_time_ms::Int32
    connections::Pool{InetAddr,Tuple{TCPSocket,Dates.DateTime}} =
        Pool{InetAddr,Tuple{TCPSocket,Dates.DateTime}}(100)
    lock::ReadWriteLock = ReadWriteLock()
    closed::Bool = false
    acquired_connections::AtomicCounter = AtomicCounter(0)
end

"""
Defines the tcp protocol. It holds a binding to an IP+Port and a tcp connection pool.
"""
@kwdef mutable struct TCPProtocol <: Protocol{InetAddr}
    address::InetAddr
    server::Union{Nothing,TCPServer} = nothing
    pool::TCPConnectionPool = TCPConnectionPool(keep_alive_time_ms=100000)
end

"""
    close(pool::TCPConnectionPool)

Close the pool. This closes all connections. Further, this function
will wait until all connection are released.
"""
function close(pool::TCPConnectionPool)
    lock(pool.lock)

    pool.closed = true

    # Waiting until all acquired connections are released
    wait(Threads.@spawn begin
        while pool.acquired_connections.counter > 0
            sleep(0.0001)
        end
    end)

    for (_, v) in pool.connections.keyedvalues
        for (connection, __) in v
            close(connection)
        end
    end
    drain!(pool.connections)

    unlock(pool.lock)
end

"""
Internal, checks whether a connection shall be kept alive 
"""
function is_valid(connection::Tuple{TCPSocket,Dates.DateTime}, keep_alive_time_ms::Int32)
    if (Dates.now() - connection[2]).value > keep_alive_time_ms
        close(connection[1])
        return false
    end
    return true
end

"""
    acquire_tcp_connection(tcp_pool::TCPConnectionPool, key::InetAddr)::Union{TCPSocket,Nothing}

Acquire a tcp connection from the pool for the key (IP+Port). Return a TCPSocket if the pool is not closed
yet, otherwise `nothing` will be returned
"""
function acquire_tcp_connection(tcp_pool::TCPConnectionPool, key::InetAddr)::Union{TCPSocket,Nothing}
    readlock(tcp_pool.lock)

    if tcp_pool.closed
        readunlock(tcp_pool.lock)
        return nothing
    end

    connection, _ = acquire(
        tcp_pool.connections,
        key,
        forcenew=false,
        isvalid=c -> is_valid(c, tcp_pool.keep_alive_time_ms),
    ) do
        result = (connect(key.host, key.port), Dates.now())
        return result
    end

    @atomic tcp_pool.acquired_connections.counter += 1

    readunlock(tcp_pool.lock)

    return connection
end

"""
    release_tcp_connection(
    tcp_pool::TCPConnectionPool,
    key::InetAddr,
    connection::TCPSocket,
)

Release the given tcp `connection` indexed by the `key`. This will put the connection back
to the pool.
"""
function release_tcp_connection(
    tcp_pool::TCPConnectionPool,
    key::InetAddr,
    connection::TCPSocket,
)
    release(tcp_pool.connections, key, (connection, Dates.now()))
    @atomic tcp_pool.acquired_connections.counter -= 1
end

"""
    send(protocol::TCPProtocol, destination::InetAddr, message::Vector{UInt8})

Send a message `message` over plain TCP using `destination` as destination address. The message has to be provided 
as a form, which is writeable to an arbitrary IO-Stream.

Return true if successfull.
"""
function send(protocol::TCPProtocol, destination::InetAddr, message::Vector{UInt8})
    @debug "Attempt to connect to $(destination.host):$(destination.port)"
    connection = acquire_tcp_connection(protocol.pool, destination)

    if isnothing(connection)
        return false
    end

    try
        length_bytes = reinterpret(UInt8, [length(message)])

        write(connection, [length_bytes; message])
        flush(connection)
    finally
        @debug "Release $(destination.host):$(destination.port)"
        release_tcp_connection(protocol.pool, destination, connection)
    end

    return true
end


"""
    parse_id(_::TCPProtocol, id::Any)::InetAddr

"""
function parse_id(_::TCPProtocol, id::Any)::InetAddr
    if typeof(id) == InetAddr
        return id
    end

    if typeof(id) == Dict{String,Any}
        return InetAddr(string(id["host"]["host"]), id["port"])
    end

    if typeof(id) == String
        ip, port = split(id, ":")
        return InetAddr(ip, parse(UInt16, port))
    end
end

"""
Internal function for handling incoming connections
"""
function handle_connection(data_handler::Function, connection::TCPSocket)
    try
        while !eof(connection)
            # Get the client address
            @debug "Process $connection"
            client_address = getpeername(connection)
            client_ip, client_port = client_address

            message_length = reinterpret(Int64, read(connection, 8))[1]
            message_bytes = read(connection, message_length)

            data_handler(message_bytes, InetAddr(client_ip, client_port))
        end

    catch err
        if !isa(err, Base.IOError)
            @error "connection job exited with unexpected error" exception =
                (err, catch_backtrace())
        end
    finally
        close(connection)
    end
end

"""
    init(protocol::TCPProtocol, stop_check::Function, data_handler::Function)

Initialized the tcp protocol. This starts the receiver and stop loop. The receiver loop
will call the data_handler with every incoming message. Further it provides as sender adress
a InetAddr object. 
"""
function init(protocol::TCPProtocol, stop_check::Function, data_handler::Function)

    server = listen(protocol.address.host, protocol.address.port)

    @debug "Listen on $(protocol.address.host):$(protocol.address.port)"

    protocol.server = server
    tasks = []
    listen_task = errormonitor(
        Threads.@spawn begin
            try
                while isopen(server)
                    connection = accept(server)
                    push!(
                        tasks,
                        @spawnlog handle_connection(data_handler, connection)
                    )
                end
            catch err
                if isa(err, InterruptException) || isa(err, Base.IOError)
                    # nothing
                else
                    @error "Caught an unexpected error in listen" exception =
                        (err, catch_backtrace())
                end
            finally
                close(server)
            end
        end
    )

    return listen_task, tasks
end

"""
    id(protocol::TCPProtocol)

Return the technical address of the protocol (ip + port)
"""
function id(protocol::TCPProtocol)::InetAddr
    return protocol.address
end

"""
    close(protocol::TCPProtocol)

Release all tcp resources (binding on port and connections in the pool).
"""
function close(protocol::TCPProtocol)
    close(protocol.pool)
    close(protocol.server)
end
