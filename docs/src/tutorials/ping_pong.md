# Tutorial: Ping-Pong with TCP

This tutorial walks through building a complete two-agent system from scratch: two agents exchange "Ping" and "Pong" messages over a TCP connection, each counting how many messages it has received. By the end you will have seen every major concept of Mango.jl in action.

!!! tip "Express API"
    If you just want a quick working example, jump straight to [Step 6](@ref step-6-using-the-express-api). The express API wraps everything in a single call.

---

## Step 1 — Install Mango.jl

```julia
using Pkg
Pkg.add("Mango")
```

---

## Step 2 — Define the Agent

Every Mango.jl agent is a Julia struct annotated with the `@agent` macro. The macro adds internal fields that the framework needs (scheduler, context, etc.), so you only declare the *application* fields you care about:

```julia
using Mango

@agent struct PingPongAgent
    counter::Int
end
```

That is all it takes to define an agent. No base class to inherit from, no interface to implement.

---

## Step 3 — Handle Incoming Messages

Agents respond to messages by adding a method to `handle_message`. The method receives the agent, the message content, and a metadata dictionary:

```julia
function Mango.handle_message(agent::PingPongAgent, message::Any, meta::Any)
    agent.counter += 1

    if message == "Ping"
        reply_to(agent, "Pong", meta)
    elseif message == "Pong"
        reply_to(agent, "Ping", meta)
    end
end
```

`reply_to` is a convenience function that sends a message back to whoever sent the current one. It uses the sender address stored in `meta`, so you never have to manage addresses manually when replying.

!!! note "Default handle_message"
    If you do not define `handle_message` for your agent type, the default implementation does nothing. This is intentional — not every agent needs to handle every message type.

---

## Step 4 — Create Containers and Register Agents

Agents live in **containers**. The container routes messages and manages the network protocol. For TCP each container binds to a host/port pair:

```julia
container1 = create_tcp_container("127.0.0.1", 5555)
container2 = create_tcp_container("127.0.0.1", 5556)

ping_agent = register(container1, PingPongAgent(0))
pong_agent = register(container2, PingPongAgent(0))
```

`register` returns the agent with its AID assigned. AIDs are strings like `"agent0"`, `"agent1"`, etc. You can also supply a custom AID:

```julia
ping_agent = register(container1, PingPongAgent(0), "ping")
pong_agent = register(container2, PingPongAgent(0), "pong")
```

---

## Step 5 — Start, Run, and Shutdown

Use `activate` to start the containers, run your code, and shut everything down automatically — even if an error occurs:

```julia
activate([container1, container2]) do
    # Kick off the exchange with the first message
    send_message(ping_agent, "Ping", address(pong_agent))

    # Wait until at least 5 messages have been exchanged
    sleep_until(() -> ping_agent.counter >= 5)
end

println("Ping agent received: $(ping_agent.counter) messages")
println("Pong agent received: $(pong_agent.counter) messages")
```

`address(agent)` returns an `AgentAddress` struct that carries the agent's AID and the container's network address. `sleep_until` polls a condition at regular intervals and returns once it is true.

!!! warning "Don't forget activate"
    Calling `start(container)` and `shutdown(container)` manually is error-prone — it is easy to forget shutdown or to miss it on an exception. Always prefer `activate`.

### Complete standalone script

```julia
using Mango

@agent struct PingPongAgent
    counter::Int
end

function Mango.handle_message(agent::PingPongAgent, message::Any, meta::Any)
    agent.counter += 1
    if message == "Ping"
        reply_to(agent, "Pong", meta)
    elseif message == "Pong"
        reply_to(agent, "Ping", meta)
    end
end

container1 = create_tcp_container("127.0.0.1", 5555)
container2 = create_tcp_container("127.0.0.1", 5556)

ping_agent = register(container1, PingPongAgent(0))
pong_agent = register(container2, PingPongAgent(0))

activate([container1, container2]) do
    send_message(ping_agent, "Ping", address(pong_agent))
    sleep_until(() -> ping_agent.counter >= 5)
end

println("Done — ping: $(ping_agent.counter), pong: $(pong_agent.counter)")
```

---

## [Step 6 — Using the Express API](@id step-6-using-the-express-api)

For common setups, the express API reduces all of the above to a single call. `run_with_tcp` creates the containers, distributes the agents, runs your setup block, and tears everything down. Using the same `PingPongAgent` definition from above:

```julia
ping_agent = PingPongAgent(0)
pong_agent = PingPongAgent(0)

run_with_tcp(2, ping_agent, pong_agent) do container_list
    send_message(ping_agent, "Ping", address(pong_agent))
    sleep_until(() -> ping_agent.counter >= 5)
end
```

The first argument to `run_with_tcp` is the number of containers to create. Agents are distributed round-robin across them.

---

## What's Next?

- **Add roles** to structure the agent's behavior → [Roles](@ref)
- **Run a simulation** without network overhead → [Simulation](@ref)
- **Build a topology** to model structured communication → [Topology](@ref)
- **Schedule proactive tasks** → [Scheduling](@ref)
