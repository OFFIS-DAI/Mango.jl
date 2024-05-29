# Mango.jl Container Feature User Documentation

Welcome to the user documentation for the Container feature in Mango.jl! This module is a fundamental part of the Mango.jl framework, providing functionalities for managing agents, handling messages, and enabling communication within the simulation environment.

## 1. Introduction

The Container feature in Mango.jl allows you to create and manage a container, which acts as the communication layer within the simulation environment. The container is responsible for handling messages, forwarding them to the appropriate agents, and managing agent registration.

## 2. Container Struct 

The `Container` struct represents the container as an actor within the simulation. It is implemented using composition, making it flexible to use different protocols and codecs for message communication. The key components of the `Container` struct are:

- `protocol`: The protocol used for message communication (e.g., TCP).
- `codec`: A pair of functions for encoding and decoding messages in the container.

## 3. Start and Shutdown 

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

## 4. Registering Agents 

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

## 5. Sending Messages

To send messages between agents within the container, you can use the `send_message` function. The container routes the message to the specified receiver agent based on the receiver's AID.

```julia
using Mango

# Create a container instance
container = Container()

# ... Register agents ...

# Sending a message from one agent to another
send_message(container, "Hello from Agent 1!", "agent2_id")
```

## 6. TCP

This protocol allows communication over plain TCP connections, enabling message exchange between different entities within the Mango.jl simulation environment.

### 1. Introduction

The TCP Protocol in Mango.jl is a communication protocol used to exchange messages over plain TCP connections. It enables agents within the simulation environment to communicate with each other by establishing and managing TCP connections.

### 2. TCPProtocol Struct 

The `TCPProtocol` struct represents the TCP Protocol within Mango.jl. It encapsulates the necessary functionalities for communication via TCP connections. Key features of the `TCPProtocol` struct are:

- `address`: The `InetAddr` represents the address on which the TCP server listens.
- `server`: A `TCPServer` instance used for accepting incoming connections.

### 3. Usage

To use the tcp protocol you need to construct a TCPProtocol struct and assign it to the `protocol` field in the container.

```julia
container2 = Container()
container2.protocol = TCPProtocol(address=InetAddr(ip"127.0.0.2", 2940))
```
