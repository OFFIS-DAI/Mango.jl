using Mango
using Test
using Parameters
using Sockets: InetAddr, @ip_str
using Base.Threads
using OrderedCollections

import Mango.AgentCore.handle_message


function handle_message(agent::MyAgent, message::Any, meta::AbstractDict)
    agent.counter += 10
end


@testset "InternalContainerMessaging" begin
    container = Container()
    agent1 = MyAgent(0)
    agent2 = MyAgent(0)
    register(container, agent1)
    register(container, agent2)

    wait(Threads.@spawn send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid)))

    @test agent1.counter == 10
end

@testset "TCPContainerMessaging" begin
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2939))
    agent1 = MyAgent(0)
    register(container, agent1)

    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2940))
    agent2 = MyAgent(0)
    register(container2, agent2)
    agent3 = MyAgent(0)
    register(container2, agent3)

    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    wait(
        send_message(
            container2,
            "Hello Friends2, this is RSc!",
            AgentAddress(aid=agent3.aid, address=InetAddr(ip"127.0.0.1", 2940))
        ),
    )

    wait(Threads.@spawn begin
        while agent3.counter != 10
            sleep(1)
        end
    end)

    @sync begin
        Threads.@spawn shutdown(container)
        Threads.@spawn shutdown(container2)
    end

    @test agent3.counter == 10
end

@agent struct PingPongAgent
    counter::Int
end

function handle_message(agent::PingPongAgent, message::Any, meta::AbstractDict)
    if message == "Ping" && agent.counter < 5
        agent.counter += 1
        send_message(agent, "Pong", AgentAddress(aid=meta["sender_id"], address=meta["sender_addr"]))
    elseif message == "Pong" && agent.counter < 5
        agent.counter += 1
        send_message(agent, "Ping", AgentAddress(aid=meta["sender_id"], address=meta["sender_addr"]))
    end
end

@testset "TCPContainerPingPong" begin
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2939))
    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2940))

    ping_agent = PingPongAgent(0)
    pong_agent = PingPongAgent(0)

    register(container2, ping_agent)
    register(container, pong_agent)

    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    wait(send_message(ping_agent, "Ping", AgentAddress(aid=pong_agent.aid, address=InetAddr(ip"127.0.0.1", 2939))))

    wait(Threads.@spawn begin
        while ping_agent.counter < 5
            sleep(1)
        end
    end)

    @sync begin
        Threads.@spawn shutdown(container)
        Threads.@spawn shutdown(container2)
    end

    @test ping_agent.counter >= 5
end


@agent struct MyRespondingAgentTCP
    counter::Integer
end
@agent struct MyTrackedAgentTCP
    counter::Integer
end

function handle_message(agent::MyRespondingAgentTCP, message::Any, meta::Any)
    agent.counter += 10
    reply_to(agent, "Hello Agents, this is DialogRespondingRico", meta)
end

function handle_response(agent::MyTrackedAgentTCP, message::Any, meta::Any)
    agent.counter = 1337
end

@testset "TCPTrackedMessages" begin

    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2939))
    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 2940))

    tracked_agent = MyTrackedAgentTCP(0)
    responding_agent = MyRespondingAgentTCP(0)

    register(container2, tracked_agent)
    register(container, responding_agent)

    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    wait(send_tracked_message(tracked_agent, "Hello Agent, this is DialogRico", AgentAddress(aid=responding_agent.aid, address=InetAddr(ip"127.0.0.1", 2939)); 
                              response_handler=handle_response))

    wait(Threads.@spawn begin
        while tracked_agent.counter == 0
            sleep(1)
        end
    end)
                              
    @sync begin
        Threads.@spawn shutdown(container)
        Threads.@spawn shutdown(container2)
    end


    @test responding_agent.counter == 10
    @test tracked_agent.counter == 1337
end
