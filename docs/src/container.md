# Real Time Container

The real time container feature in Mango.jl allows you to create and manage a container, which acts as the communication layer within the environment. A container is responsible for handling messages, forwarding them to the appropriate agents, and managing agent registration. The real time component means that the container acts on a real time clock, and does not differentiate between a simulation time and the execution time, which essentially means everything executed withing the real time container is executed immediately as stated in the code. In contrast, there is also a "simulation" container, which maintains an interal simulation time and only executes tasks and delivers messages according to the requested step_sizes (next event time). More on the simulation container can be found under [Simulation Container](@ref). Note, that both container types implement the methods for the [`ContainerInterface`](@ref) and can therefore be drop-in replacements for the each other with slight differences in usage.

## Container Struct 

The [`Container`](@ref) struct represents the container as an actor within the environment. It is implemented using composition, making it flexible to use different protocols and codecs for message communication. The key components of the [`Container`](@ref) struct are:

- `protocol`: The protocol used for message communication (e.g., TCP).
- `codec`: A pair of functions for encoding and decoding messages in the container.

## Start and Shutdown 

Before using the container for message handling and agent management, you need to start the container using the [`start`](@ref) function. This function initializes the container's components and enables it to act as the communication layer. After you are done with the container, [`shutdown`](@ref) has to be called.

```@example
using Mango

# Create a container instance
container = Container()

# ... setup the container, agents, define handles, ...

# Start the container
wait(Threads.@spawn start(container))

# Execute some functionality to e.g. trigger the agent system

# Shut down the container
shutdown(container)
@info "Agent container and agents shutdown"
```

However, this approach can be error-prone for multiple reasons. Besides simply forgetting to call shutdown, an exception may occur between the start and shutdown calls on the containers, leading to resource leaks. For this reason, we recommend using [`activate`](@ref) instead. With this function, the above `start/shutdown' pair translates to...

```julia
# Start the container and shut it down after the runnable (do ... end) has been executed.
activate(container) do

# Execute some functionality to e.g. trigger the agent system

end
```

## Registering Agents 

To enable the container to manage agents and handle their messaging activities, you can register agents using the [`register`](@ref) function. This function associates an agent with a unique agent ID (AID) and adds the agent to the container's internal list.

```@example
using Mango

# Create a container instance
container = Container()

# Define and create an agent
@agent struct MyAgent
    # Your agent's fields and methods here
end

my_agent = MyAgent()

# Register the agent with the container
register(container, my_agent)
```

## Sending Messages

To send messages between agents within the container, you can use the [`send_message`](@ref) function. The container routes the message to the specified receiver agent based on the receiver's AID.

```@example
using Mango

# Create a container instance
container = Container()
agent = register(container, PrintingAgent())

# ... Register agents ...

# Sending a message from one agent to another
wait(send_message(container, "Hello from Agent 1!", address(agent)))
```

## TCP

This protocol allows communication over plain TCP connections, enabling message exchange between different entities within the Mango.jl simulation environment.

### Introduction

The TCP Protocol in Mango.jl is a communication protocol used to exchange messages over plain TCP connections. It enables agents within the simulation environment to communicate with each other by establishing and managing TCP connections.

### TCPProtocol Struct 

The [`TCPProtocol`](@ref) struct represents the TCP Protocol within Mango.jl. It encapsulates the necessary functionalities for communication via TCP connections. Key features of the [`TCPProtocol`](@ref) struct are:

- `address`: The `InetAddr` represents the address on which the TCP server listens.
- `server`: A `TCPServer` instance used for accepting incoming connections.

### Usage

To use the tcp protocol you need to construct a TCPProtocol struct and assign it to the `protocol` field in the container.

```@example
using Mango, Sockets

container2 = Container()
container2.protocol = TCPProtocol(address=Sockets.InetAddr("127.0.0.2", 2940))
```

It is also possible to use the convenience function [`create_tcp_container`](@ref).

```@example
using Mango 

container2 = create_tcp_container("127.0.0.2", 2940)
```

## MQTT
### Introduction
The MQTT protocol enables sending via an MQTT message broker.
It allows a container to subscribe to different topics on a broker and publish messages to them.

Currently, one container may only connect to a single broker.
Subscribed topics for each agent are set on agent registration and tracked by the container.
Incoming messages on these topics are distributed to the subscribing agents by the container.

### MQTTProtocol Struct 
The [`MQTTProtocol`](@ref) contains the status and channels of the underlying mosquitto C library (as abstracted to Julia by the Mosquitto.jl package).

The constructor takes a `client_id` and the `broker_addr`.
Internally it also tracks the `msg_channel` and `conn_channel`, internal flags, the information to map topics to subscribing agents.

`protocol = MQTTProtocol(cliant_id, broker_addr)`
- `client_id` - `String` id the container will communicate to the MQTT broker.
- `broker_addr` - `InetAddr` of the MQTT broker

### Usage

To use the mqtt protocol you need to construct a MQTTProtocol struct and assign it to the `protocol` field in the container. Further it is possible to use a convenience function for this 
It is also possible to use the convenience function [`create_mqtt_container`](@ref).
```julia
using Mango, Sockets

container2 = Container()
container2.protocol = MQTTProtocol("my_id", Sockets.InetAddr(ip"127.0.0.2", 2940))
```

!!! note "Running MQTT broker expected"
    The MQTT protocol expects an MQTT broker to run at the specified host and port.

Subscribing an agent to a topic can happen only as registration time and is not allowed otherwise.
When registering a new agent to the container the topics to subscribe are passed by the `topics` keyword argument, taking a collection of `String` topic names.
NOTE: It is recommended you pass a `Vector{String}` as this is what is tested. 
Other collections could work but no guarantees are given.

```julia
using Mango

container2 = create_mqtt_container("127.0.0.2", 2940, "MyMqttClient")

a1 = PrintingAgent()
register(container2, a1; topics=["topic1", "topic2"])
```