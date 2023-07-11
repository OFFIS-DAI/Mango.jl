
export TCPAddress, TCPProtocol, send, init

using Sockets: connect, write, close, getpeername, read, listen, accept, IPAddr, TCPServer, TCPSocket, @ip_str, InetAddr
using Parameters
using ..AsyncUtil

@with_kw mutable struct TCPProtocol <: Protocol{InetAddr}
    address::InetAddr
    server::Union{Nothing,TCPServer} = nothing
    connections::Dict{InetAddr,TCPServer} = Dict()
end


function send(protocol::TCPProtocol, destination::InetAddr, message::Any)
    @info "Attempt to connect to $(destination.host):$(destination.port)"
    connection = connect(destination.host, destination.port)

    write(connection, message)

    @info "Close $(destination.host):$(destination.port)"
    close(connection)
    return true
end

function handle_connection(data_handler::Function, connection::TCPSocket)
    try
        while !eof(connection)        
            # Get the client address
            @debug "Process $connection"
            client_address = getpeername(connection)
            client_ip, client_port = client_address
    
            bytes = read(connection)
        
            data_handler(bytes, InetAddr(client_ip, client_port))
        end

    catch err
        if !isa(err, Base.IOError)
            @error "connection job exited with unexpected error" exception=(err, catch_backtrace())
        end
    finally
        close(connection)
    end
end

function init(protocol::TCPProtocol, stop_check::Function, data_handler::Function)

    server = listen(protocol.address.host, protocol.address.port)

    @info "Listen on $(protocol.address.host):$(protocol.address.port)"
    
    protocol.server = server

    listen_task = errormonitor(@async begin
        try
            while isopen(server)
                connection = accept(server)
                @asynclog handle_connection(data_handler, connection)
            end
        catch err
            if isa(err, InterruptException)
                # expected exit behavior
            else
                @error "Caught an unexpected error in listen" exception=(err, catch_backtrace())
            end
        finally
            close(server)
        end
    end)

    error_task = errormonitor(@async begin
        while !stop_check()
            sleep(0.1)
        end
        @async Base.throwto(listen_task, InterruptException())
    end)

    #wait(listen_task)
    #wait(error_task)
    @info "Starting TCP: Done"
end
