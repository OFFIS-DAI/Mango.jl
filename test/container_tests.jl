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

@agent struct PingPongAgent
    counter::Int
end

function handle_message(agent::PingPongAgent, message::Any, meta::Dict)
    if message == "Ping"
        agent.counter += 1
        send_message(agent, "Pong", meta["sender_id"], meta["sender_addr"])
    elseif message == "Pong"
        agent.counter += 1
        send_message(agent, "Ping", meta["sender_id"], meta["sender_addr"])
    end
end

@testset "TCPContainerPingPong" begin
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2980))
    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2981))

    ping_agent = PingPongAgent(0)
    pong_agent = PingPongAgent(0)
    register(container2, ping_agent)
    register(container, pong_agent)

    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    send_message(ping_agent, "Ping", pong_agent.aid, InetAddr(ip"127.0.0.2", 2980))
    
    wait(@async begin
        while ping_agent.counter < 5 
            sleep(1)
        end
    end)
    
    @sync begin
        @async shutdown(container)
        @async shutdown(container2)
    end

    @test ping_agent.counter >= 5
end