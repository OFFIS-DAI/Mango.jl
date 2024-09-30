# Getting Started with Mango.jl

In this getting started guide, we will explore the essential features of Mango.jl, starting with a simple example using the express-api, followed by a more in-depth example of two ping pong agents that exchange messages in a container. Here, we will manually set up a container with the TCP protocol, define ping pong agents, and enable them to exchange messages. This way allows better customization but may need more boilerplate code.

You can also find working examples of the following code in [examples.jl](../../test/examples.jl).

## 0. Quickstart

In Mango.jl, you can define agents using a number of roles using [`@role`](@ref) and [`agent_composed_of`](@ref), or directly using [`@agent`](@ref). To define the behavior of the agents, [`handle_message`](@ref) can be defined, and messages can be send using [`send_message`](@ref). To run the agents with a specific protocol in real time the fastest way is to use [`run_with_tcp`](@ref), which will distribute the agents to tcp-containers and accepts a function in which some agent intializiation and/or trigger-code could be put. The following example illustrates the basic usage of the functions.

```jldoctest
using Mango

@role struct PrintingRole
    out::Any = ""
end

function Mango.handle_message(role::PrintingRole, msg::Any, meta::AbstractDict)
    role.out = msg
end

express_one = agent_composed_of(PrintingRole())
express_two = agent_composed_of(PrintingRole(), PrintingRole())

run_with_tcp(2, express_one, express_two) do container_list
    wait(send_message(express_one, "Ping", address(express_two)))
    sleep_until(() -> express_two[1].out == "Ping")
end

# evaluating
express_two[1].out
# output
"Ping"
```

## Step-by-step (manual container creation)

Alternatively you can create the container yourself. This is the more flexible approach, but also wordier.

### 1. Creating a Container with a TCP Protocol

we need to create a container to manage ping pong agents and facilitate communication using the TCP protocol:

```@example tcp_gs
using Mango, Sockets

# Create the container instances with TCP protocol
container = create_tcp_container("127.0.0.1", 5555)
container2 = create_tcp_container("127.0.0.1", 5556)
```

### 2. Defining Ping Pong Agents

Let's define agent structs to represent the ping pong agents. Every new agent struct should be defined using the @agent macro to ensure compatibility with the mango container:

```@example tcp_gs
# Define the ping pong agent
@agent struct TCPPingPongAgent
    counter::Int
end
```

### 3. Sending and Handling Messages

Ping pong agents can exchange messages and they can keep track of the number of messages received. Let's implement message handling for the agents. To achieve this a new method [`handle_message`](@ref) from `Mango` has to be added:

```@example tcp_gs
# Override the default handle_message function for ping pong agents
function Mango.handle_message(agent::TCPPingPongAgent, message::Any, meta::Any)
    agent.counter += 1

    println(
        "$(agent.aid) got a message: $message." *
        "This is message number: $(agent.counter) for me!"
    )

    # doing very important work
    sleep(0.5)

    if message == "Ping"
        reply_to(agent, "Pong", meta)
    elseif message == "Pong"
        reply_to(agent, "Ping", meta)
    end
end
```

### 4. Sending Messages

Now let's simulate the ping pong exchange by sending messages between the ping pong agents. 
Addresses are provided to the [`send_message`](@ref) function via the [`AgentAddress`](@ref) struct.
The struct consists of an `aid` and the more technical `address` field. Further an AgentAddress 
can contain a `tracking_id`, which can identify the dialog agents are having.

The [`send_message`](@ref) method here will automatically insert the agent as sender:

```@example tcp_gs
# Define the ping pong agent
# Create instances of ping pong agents
ping_agent = register(container, TCPPingPongAgent(0))
pong_agent = register(container2, TCPPingPongAgent(0))

activate([container, container2]) do
    # Send the first message to start the exchange
    send_message(ping_agent, "Ping", address(pong_agent))

    # wait for 5 messages to have been sent
    sleep_until(() -> ping_agent.counter >= 5)
end
```

In this example, the ping pong agents take turns sending "Ping" and "Pong" messages to each other, incrementing their counters. After a short moment, we can see the result of the ping pong process.

### 5. Using the MQTT Protocol
To use an MQTT messsage broker instead of a direkt TCP connection, you can use the MQTT protocol. This protocol requires a running MQTT broker. For this you can, for example, use Mosquitto as broker. On most linux-based systems mosquitto exists as package in the public repostories. For example for debian systems:

```bash
sudo apt install mosquitto
sudo service mosquitto start
```

After, you can create MQTT container.

```julia
using Mango

c1 = create_mqtt_container("127.0.0.1", 1883, "PingContainer")
c2 = create_mqtt_container("127.0.0.1", 1883, "PongContainer")
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
# register each agent to a container
# For the MQTT protocol, topics for each agent have to be passed here.
ping_agent = register(c1, MQTTPingPongAgent(0); topics=["pongs"])
pong_agent = register(c2, MQTTPingPongAgent(0); topics=["pings"])
```

Just like the TCPProtocol, the MQTTProtocol has an associated struct for providing address information:
* the broker address
* the topic

Thus, sending of the first message and the handle_message definition becomes:

Lastly, [`handle_message`](@ref) has to be altered to send the corresponding answers correctly:

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

activate([c1, c2]) do
    # Send the first message to start the exchange
    send_message(ping_agent, "Ping", MQTTAddress(broker_addr, "pings"))
    sleep_until(() -> ping_agent.counter >= 5)
end
```
