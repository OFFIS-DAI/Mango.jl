"""
This file contains all examples given in the documentation enclosed in julia testsets.
This is to catch example code breaking on changes to the framework.
"""

using Mango
using Test
using Parameters
using TestItems
using Sockets: InetAddr, @ip_str


@testset "SEND_AFTER_CLOSE" begin
    addr = InetAddr(ip"127.0.0.1", 5555)
    protocol = TCPProtocol(address=addr)
    
    loop, tasks = init(
        protocol,
        () -> nothing,
        (msg_data, sender_addr; receivers=nothing) -> nothing,
    )

    close(protocol)
    res = send(protocol, addr, Vector{UInt8}())

    @test !res
end

@testset "CLOSE_WHILE_AC" begin
    addr = InetAddr(ip"127.0.0.1", 5555)
    protocol = TCPProtocol(address=addr)
    
    loop, tasks = init(
        protocol,
        () -> nothing,
        (msg_data, sender_addr; receivers=nothing) -> nothing,
    )

    connection = acquire_tcp_connection(protocol.pool, addr)
    task = Threads.@spawn begin
        sleep(0.1)
        release_tcp_connection(protocol.pool, addr, connection)
    end
    close(protocol)
    
    @test length(protocol.pool.connections.keyedvalues[InetAddr(ip"127.0.0.1", 5555)]) == 0
end