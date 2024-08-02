# Real Time Container

The real time container feature in Mango.jl allows you to create and manage a container, which acts as the communication layer within the environment. A container is responsible for handling messages, forwarding them to the appropriate agents, and managing agent registration. The real time component means that the container acts on a real time clock, and does not differentiate between a simulation time and the execution time, which essentially means everything executed withing the real time container is executed immediately as stated in the code. In contrast, there is also a "simulation" container, which maintains an interal simulation time and only executes tasks and delivers messages according to the requested step_sizes (next event time). More on the simulation container can be found under [Simulation Container](@ref). Note, that both container types implement the methods for the `ContainerInterface` and can therefore be drop-in replacements for the each other with slight differences in usage.

## Container Struct 

The `Container` struct represents the container as an actor within the environment. It is implemented using composition, making it flexible to use different protocols and codecs for message communication. The key components of the `Container` struct are:

- `protocol`: The protocol used for message communication (e.g., TCP).
- `codec`: A pair of functions for encoding and decoding messages in the container.

## Start and Shutdown 

Before using the container for message handling and agent management, you need to start the container using the `start` function. This function initializes the container's components and enables it to act as the communication layer.

```julia
using Mango

# Create a container instance
container = Container()

# Start the container
wait(Threads.@spwan start(container))

# ... Perform message handling and agent registration ...
# ... When done, shut down the container ...

# Shut down the container
shutdown(container)
```

## Registering Agents 

To enable the container to manage agents and handle their messaging activities, you can register agents using the `register` function. This function associates an agent with a unique agent ID (AID) and adds the agent to the container's internal list.

```julia
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

To send messages between agents within the container, you can use the `send_message` function. The container routes the message to the specified receiver agent based on the receiver's AID.

```julia
using Mango

# Create a container instance
container = Container()

# ... Register agents ...

# Sending a message from one agent to another
send_message(container, "Hello from Agent 1!", "agent2_id")
```

## TCP

This protocol allows communication over plain TCP connections, enabling message exchange between different entities within the Mango.jl simulation environment.

### Introduction

The TCP Protocol in Mango.jl is a communication protocol used to exchange messages over plain TCP connections. It enables agents within the simulation environment to communicate with each other by establishing and managing TCP connections.

### TCPProtocol Struct 

The `TCPProtocol` struct represents the TCP Protocol within Mango.jl. It encapsulates the necessary functionalities for communication via TCP connections. Key features of the `TCPProtocol` struct are:

- `address`: The `InetAddr` represents the address on which the TCP server listens.
- `server`: A `TCPServer` instance used for accepting incoming connections.

### Usage

To use the tcp protocol you need to construct a TCPProtocol struct and assign it to the `protocol` field in the container.

```julia
container2 = Container()
container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2940))
```
