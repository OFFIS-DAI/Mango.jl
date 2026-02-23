# Real-Time Container

The **container** is the message router of a Mango.jl agent system. Every agent must be registered in a container. The container:

- assigns a unique AID to each agent
- routes incoming messages to the correct agent by AID
- manages the underlying network protocol (TCP or MQTT)

!!! note "This page covers real-time mode only"
    A Mango.jl system uses either a real-time **Container** (this page) or a simulation **[`World`](@ref)** — not both. The `World` replaces the container entirely when running simulations: it has no network, advances a virtual clock, and delivers messages through an in-process queue. Because both implement the same `ContainerInterface`, your agent code works unchanged in either mode. See [Simulation](@ref) for details.

---

## Creating a Container

### TCP

The most common protocol for local and distributed agent communication:

```@example tcp_container
using Mango

container1 = create_tcp_container("127.0.0.1", 5555)
container2 = create_tcp_container("127.0.0.1", 5556)
```

Or construct manually for full control over the protocol:

```julia
container = Container()
container.protocol = TCPProtocol(address=InetAddr("127.0.0.2", 2940))
```

### MQTT

MQTT uses a message broker for routing. Every container connects to the same broker; agents subscribe to topics and publish to other topics.

!!! note "Broker required"
    An MQTT broker (e.g. Mosquitto) must be running before the container is started.
    ```bash
    sudo apt install mosquitto
    sudo service mosquitto start
    ```

```julia
c1 = create_mqtt_container("127.0.0.1", 1883, "ClientA")
c2 = create_mqtt_container("127.0.0.1", 1883, "ClientB")
```

Or manually:

```julia
container = Container()
container.protocol = MQTTProtocol("my_client_id", InetAddr(ip"127.0.0.1", 1883))
```

### Protocol comparison

| | **TCP** | **MQTT** |
|---|---|---|
| Routing | Direct TCP connections | Via broker with topics |
| Address type | `AgentAddress` | `MQTTAddress(broker, topic)` |
| Broker needed | No | Yes |
| Registration extra | — | `topics=["t1", "t2"]` |
| Best for | Local multi-container setups | IoT, cloud, multi-network |

---

## Registering Agents

```@example tcp_reg
using Mango

container = Container()

@agent struct RegAgent end

agent1 = register(container, RegAgent())           # auto AID: "agent0"
agent2 = register(container, RegAgent(), "ctrl")   # custom AID: "ctrl"
```

For MQTT containers, pass `topics` to subscribe the agent to one or more broker topics:

```julia
agent = register(mqtt_container, MyAgent(); topics=["sensor/data", "sensor/alerts"])
```

All messages published to those topics on the broker are forwarded to that agent.

---

## The activate Pattern (Recommended)

Use `activate` to start containers, run your code, and shut everything down — even if an error occurs:

```julia
# Single container
activate(container) do
    send_message(agent, "hello", address(other_agent))
    sleep_until(() -> other_agent.counter >= 3)
end

# Multiple containers — started in parallel
activate([container1, container2]) do
    send_message(ping_agent, "Ping", address(pong_agent))
    sleep_until(() -> ping_agent.counter >= 5)
end
```

!!! warning "Don't start/shutdown manually"
    While `start(container)` and `shutdown(container)` exist, calling them directly is error-prone — an exception between `start` and `shutdown` will leave the container running. Always prefer `activate`.

---

## Sending Messages

### From the container directly

```@example tcp_send
using Mango

container = Container()

@agent struct PrintAgent end

function Mango.handle_message(::PrintAgent, msg::Any, ::Any)
    @info "received" msg
end

agent = register(container, PrintAgent())

wait(send_message(container, "hello", address(agent)))
```

### Between agents over TCP

```julia
activate([c1, c2]) do
    send_message(ping_agent, "Ping", address(pong_agent))
    sleep_until(() -> pong_agent.counter >= 1)
end
```

### Between agents over MQTT

MQTT addresses carry the broker address and the destination topic. The sending side must know the receiving agent's subscribed topic:

```julia
function Mango.handle_message(agent::MyMQTTAgent, message::Any, ::Any)
    broker = agent.context.container.protocol.broker_addr
    if message == "Ping"
        send_message(agent, "Pong", MQTTAddress(broker, "pongs"))
    end
end

activate([c1, c2]) do
    broker_addr = c1.protocol.broker_addr
    send_message(ping_agent, "Ping", MQTTAddress(broker_addr, "pings"))
    sleep_until(() -> ping_agent.counter >= 5)
end
```

---

## Express API Shortcuts

The express API wraps the full container lifecycle in a single call:

```julia
# TCP — n containers, agents distributed round-robin
run_with_tcp(2, agent1, agent2, agent3) do container_list
    # ...
end

# With per-agent options — all entries must be 2-element tuples (agent, :key => val)
run_with_tcp(2, (agent1, :aid => "primary"), (agent2, :aid => "backup")) do cl
    # ...
end

# MQTT
run_with_mqtt(2, (agent1, :topics => ["pings"]), (agent2, :topics => ["pongs"])) do cl
    # ...
end
```

---

## Codec Configuration

Every container applies a codec — a `(encode, decode)` function pair — to messages before sending and after receiving. The default is BSON serialization, which is required for cross-process TCP/MQTT communication.

```julia
# Default BSON codec (applied automatically)
container = create_tcp_container("127.0.0.1", 5555)

# Custom codec
container = create_tcp_container("127.0.0.1", 5555; codec=(my_encode, my_decode))
```

For simulation containers (in-memory messaging, same process), codecs are not applied. See [Codecs](@ref) for details on the built-in BSON codec.

---

## Accessing Agents

```julia
container[1]          # first registered agent (by registration order)
container["agent0"]   # agent with AID "agent0"
agents(container)     # all agents as an ordered vector
```
