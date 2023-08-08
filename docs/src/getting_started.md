# Getting Started with Mango.jl

In this getting started guide, we will explore the essential features of Mango.jl by creating a simple simulation of two ping pong agents that exchange messages in a container. We will set up a container with the TCP protocol, define ping pong agents, and enable them to exchange messages.

## 1. Creating a Container with a Protocol

To get started, we need to create a container to manage ping pong agents and facilitate communication using the TCP protocol:

```julia
using Mango

# Create the container instances with TCP protocol
container = Container()
container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2980))

container2 = Container()
container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2981))

# Start the container
wait(Threads.@spawn start(container))
wait(Threads.@spawn start(container2))
```

## 2. Defining Ping Pong Agents

Let's define agent structs to represent the ping pong agents. Every new agent struct should be defined using the @agent macro to ensure compatibility to the mango container:

```julia
using Mango

# Define the ping pong agent
@agent struct PingPongAgent
    counter::Int
end
```

## 3. Sending and Handling Messages

Ping pong agents can exchange messages and they can keep track of the number of messages received. Let's implement message handling for the agents. To achieve this a new method `handle_message` from `Mango.AgentCore` has to be added:

```julia
import Mango.AgentCore.handle_message

# Override the default handle_message function for ping pong agents
function handle_message(agent::PingPongAgent, message::Any, meta::Dict)
    if message == "Ping"
        agent.counter += 1
        send_message(agent, "Pong", meta["sender_id"], meta["sender_addr"])
    elseif message == "Pong"
        agent.counter += 1
        send_message(agent, "Ping", meta["sender_id"], meta["sender_addr"])
    end
end
```

## 4. Sending Messages

Now let's simulate the ping pong exchange by sending messages between the ping pong agents. The `send_message` method here will automatically insert the agent as sender:

```julia
# Define the ping pong agent
# Create instances of ping pong agents
ping_agent = PingPongAgent(0)
pong_agent = PingPongAgent(0)

# Send the first message to start the exchange
send_message(ping_agent, "Ping", pong_agent.aid, InetAddr(ip"127.0.0.2", 2980))

# Wait for a moment to see the result
# In general you want to use a Condition() instead to
# Define a clear stopping signal for the agents
wait(@async begin
    while ping_agent.counter < 5 
        sleep(1)
    end
end)

@sync begin
    @async shutdown(container)
    @async shutdown(container2)
end
```

In this example, the ping pong agents take turns sending "Ping" and "Pong" messages to each other, incrementing their counters. After a short moment, we can see the result of the ping pong process.