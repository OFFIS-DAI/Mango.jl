# Getting Started with Mango.jl

In this getting started guide, we will explore the essential features of Mango.jl by creating a simple simulation of two ping pong agents that exchange messages in a container. We will set up a container with the TCP protocol, define ping pong agents, and enable them to exchange messages.
You can also find working examples of the following code in [examples.jl](../../test/examples.jl).

## 1. Creating a Container with a TCP Protocol

To get started, we need to create a container to manage ping pong agents and facilitate communication using the TCP protocol:

```julia
using Mango

# Create the container instances with TCP protocol
container = Container()
container.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5555))

container2 = Container()
container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.1", 5556))

# Start the container
wait(Threads.@spawn start(container))
wait(Threads.@spawn start(container2))
```

## 2. Defining Ping Pong Agents

Let's define agent structs to represent the ping pong agents. Every new agent struct should be defined using the @agent macro to ensure compatibility with the mango container:

```julia
using Mango

# Define the ping pong agent
@agent struct TCPPingPongAgent
    counter::Int
end
```

## 3. Sending and Handling Messages

Ping pong agents can exchange messages and they can keep track of the number of messages received. Let's implement message handling for the agents. To achieve this a new method `handle_message` from `Mango` has to be added:

```julia
import Mango.handle_message

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
```

## 4. Sending Messages

Now let's simulate the ping pong exchange by sending messages between the ping pong agents. 
Addresses are provided to the `send_message` function via the `AgentAddress` struct.

```julia
@kwdef struct AgentAddress <: Address
    aid::Union{String,Nothing}
    address::Any = nothing
    tracking_id::Union{String,Nothing} = nothing
end
```

The `send_message` method here will automatically insert the agent as sender:

```julia
# Define the ping pong agent
# Create instances of ping pong agents
ping_agent = TCPPingPongAgent(0)
pong_agent = TCPPingPongAgent(0)

# register each agent to a container
register(container, ping_agent)
register(container2, pong_agent)

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

@sync begin
    Threads.@spawn shutdown(container)
    Threads.@spawn shutdown(container2)
end
```

In this example, the ping pong agents take turns sending "Ping" and "Pong" messages to each other, incrementing their counters. After a short moment, we can see the result of the ping pong process.

## 5. Using the MQTT Protocol
To use an MQTT messsage broker instead of a direkt TCP connection, you can use the `MQTTProtocol`.

```julia
broker_addr = InetAddr(ip"127.0.0.1", 1883)

c1 = Container()
c1.protocol = MQTTProtocol("PingContainer", broker_addr)

c2 = Container()
c2.protocol = MQTTProtocol("PongContainer", broker_addr)
```

The topics each agent subscribes to on the broker are provided during registration to the container.
All messages on these topics will then be forwarded as messages to the agent.

```julia
# Define the ping pong agent
@agent struct MQTTPingPongAgent
    counter::Int
end

# Define the ping pong agent
# Create instances of ping pong agents
ping_agent = MQTTPingPongAgent(0)
pong_agent = MQTTPingPongAgent(0)

# register each agent to a container
# For the MQTT protocol, topics for each agent have to be passed here.
register(c1, ping_agent; topics=["pongs"])
register(c2, pong_agent; topics=["pings"])
```

Just like the TCPProtocol, the MQTTProtocol has an associated struct for providing address information:

```julia
@kwdef struct MQTTAddress <: Address
    broker::Any = nothing
    topic::String
end
```

Thus, sending of the first message becomes:

```julia
# Send the first message to start the exchange
wait(send_message(ping_agent, "Ping", MQTTAddress(broker_addr, "pings")))
```


Lastly, `handle_message` has to be altered to send the corresponding answers correctly:

```julia
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
```