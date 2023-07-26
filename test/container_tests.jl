using Mango
using Test
using Parameters
using Sockets: InetAddr, @ip_str
using Base.Threads

import Mango.AgentCore.handle_message


function handle_message(agent::MyAgent, message::Any, meta::Any)
    agent.counter += 10
end


@testset "InternalContainerMessaging" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    register(container, agent1)
    register(container, agent2)

    wait(@asynclog send_message(container, "Hello Friends, this is RSc!", agent1.aid))

    @test agent1.counter == 10
end

@testset "TCPContainerMessaging" begin
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2939))
    agent1 = MyAgent(0)
    register(container, agent1)
    
    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2940))
    agent2 = MyAgent(0)
    register(container2, agent2)
    agent3 = MyAgent(0)
    register(container2, agent3)
    
    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    wait(send_message(container2, "Hello Friends2, this is RSc!", agent3.aid, InetAddr(ip"127.0.0.2", 2940)))

    shutdown(container)
    shutdown(container2)

    @test agent3.counter == 10
end