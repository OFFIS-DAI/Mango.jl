"""
This file contains all examples given in the documentation enclosed in julia testsets.
This is to catch example code breaking on changes to the framework.
"""

using Mango
using Test
using Parameters
using TestItems
using Sockets: InetAddr, @ip_str

import Mango.handle_message


# Define the ping pong agent
@agent struct TCPPingPongAgent
    counter::Int
end

# Override the default handle_message function for ping pong agents
function handle_message(agent::TCPPingPongAgent, message::Any, meta::Any)
    if message == "Ping"
        agent.counter += 1
        t = AgentAddress(meta["sender_id"], meta["sender_addr"], nothing)
        send_message(agent, "Pong", t)
    elseif message == "Pong"
        agent.counter += 1
        t = AgentAddress(meta["sender_id"], meta["sender_addr"], nothing)
        send_message(agent, "Ping", t)
    end
end

@testset "TCP_AGENT" begin
    # Create the container instances with TCP protocol
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5555))

    container2 = Container()
    container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5556))


    # Define the ping pong agent
    # Create instances of ping pong agents
    ping_agent = TCPPingPongAgent(0)
    pong_agent = TCPPingPongAgent(0)

    # register each agent to a container
    register(container, ping_agent)
    register(container2, pong_agent)

    # Start the container
    wait(Threads.@spawn start(container))
    wait(Threads.@spawn start(container2))

    # Send the first message to start the exchange
    target = AgentAddress(pong_agent.aid, InetAddr(ip"127.0.0.1", 5556), nothing)
    send_message(ping_agent, "Ping", target)

    # Wait for a moment to see the result
    # In general you want to use a Condition() instead to
    # Define a clear stopping signal for the agents
    wait(Threads.@spawn begin
        while ping_agent.counter < 5
            sleep(1)
        end
    end)

    # Start the container
    @sync begin
        Threads.@spawn shutdown(container)
        Threads.@spawn shutdown(container2)
    end

    @test ping_agent.counter >= 5
end


# Define the ping pong agent
@agent struct MQTTPingPongAgent
    counter::Int
end

# Override the default handle_message function for ping pong agents
function handle_message(agent::MQTTPingPongAgent, message::Any, meta::Any)
    broker_addr = agent.context.container.protocol.broker_addr

    if message == "Ping"
        agent.counter += 1
        send_message(agent, "Pong", MQTTAddress(broker_addr, "pongs"))
    elseif message == "Pong"
        agent.counter += 1
        send_message(agent, "Ping", MQTTAddress(broker_addr, "pings"))
    end
end

@testset "MQTT_AGENT" begin
    broker_addr = InetAddr(ip"127.0.0.1", 1883)

    c1 = Container()
    c1.protocol = MQTTProtocol("PingContainer", broker_addr)

    c2 = Container()
    c2.protocol = MQTTProtocol("PongContainer", broker_addr)

    # Define the ping pong agent
    # Create instances of ping pong agents
    ping_agent = MQTTPingPongAgent(0)
    pong_agent = MQTTPingPongAgent(0)

    # register each agent to a container
    # For the MQTT protocol, topics for each agent have to be passed here.
    register(c1, ping_agent; topics=["pongs"])
    register(c2, pong_agent; topics=["pings"])

    # Start the container
    wait(Threads.@spawn start(c1))
    wait(Threads.@spawn start(c2))

    sleep(0.5)
    if !c1.protocol.connected
        return
    end

    # Send the first message to start the exchange
    wait(send_message(ping_agent, "Ping", MQTTAddress(broker_addr, "pings")))

    # Wait for a moment to see the result
    # In general you want to use a Condition() instead to
    # Define a clear stopping signal for the agents
    wait(Threads.@spawn begin
        while ping_agent.counter < 5
            sleep(1)
        end
    end)

    # Start the container
    @sync begin
        Threads.@spawn shutdown(c1)
        Threads.@spawn shutdown(c2)
    end

    @test ping_agent.counter >= 5
end