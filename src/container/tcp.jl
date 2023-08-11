
export TCPAddress, TCPProtocol, send, init, close, id, parse_id

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
using Parameters
import ..Mango: @asynclog


using ConcurrentUtilities: Pool, acquire, release, drain!

import Dates
import Base.close

@with_kw struct TCPConnectionPool
    keep_alive_time_ms::Int32
    connections::Pool{InetAddr,Tuple{TCPSocket,Dates.DateTime}} =
        Pool{InetAddr,Tuple{TCPSocket,Dates.DateTime}}(100)
end

@with_kw mutable struct TCPProtocol <: Protocol{InetAddr}
    address::InetAddr
    server::Union{Nothing,TCPServer} = nothing
    pool::TCPConnectionPool = TCPConnectionPool(keep_alive_time_ms = 100000)
end

function close(pool::TCPConnectionPool)
    for (_, v) in pool.connections.keyedvalues
        for (connection, __) in v
            close(connection)
        end
    end
    drain!(pool.connections)
end

function is_valid(connection::Tuple{TCPSocket,Dates.DateTime}, keep_alive_time_ms::Int32)
    if (Dates.now() - connection[2]).value > keep_alive_time_ms
        close(connection[1])
        return false
    end
    return true
end

function acquire_tcp_connection(tcp_pool::TCPConnectionPool, key::InetAddr)::TCPSocket
    connection, _ = acquire(
        tcp_pool.connections,
        key,
        forcenew = false,
        isvalid = c -> is_valid(c, tcp_pool.keep_alive_time_ms),
    ) do
        return (connect(key.host, key.port), Dates.now())
    end
    return connection
end

function release_tcp_connection(
    tcp_pool::TCPConnectionPool,
    key::InetAddr,
    connection::TCPSocket,
)
    release(tcp_pool.connections, key, (connection, Dates.now()))
end

"""
Send a message `message` over plain TCP using `destination` as destination address. The message has to be provided 
as a form, which is writeable to an arbitrary IO-Stream.

# Returns
Return true if successfull.
"""
function send(protocol::TCPProtocol, destination::InetAddr, message::Vector{UInt8})
    @debug "Attempt to connect to $(destination.host):$(destination.port)"
    connection = acquire_tcp_connection(protocol.pool, destination)

    length_bytes = reinterpret(UInt8, [length(message)])

    write(connection, [length_bytes; message])
    flush(connection)

    @debug "Release $(destination.host):$(destination.port)"
    release_tcp_connection(protocol.pool, destination, connection)

    return true
end


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
        @async begin
            try
                while isopen(server)
                    connection = accept(server)
                    push!(tasks, @async handle_connection(data_handler, connection))
                end
            catch err
                if isa(err, InterruptException)
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

function id(protocol::TCPProtocol)
    return protocol.address
end

"""
Release all tcp resources
"""
function close(protocol::TCPProtocol)
    close(protocol.pool)
end
