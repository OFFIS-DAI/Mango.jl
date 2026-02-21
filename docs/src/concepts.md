# Mango.jl Concepts

This page explains the core abstractions of Mango.jl and how they fit together. Reading it is not required to get started, but it will help you understand *why* the API is designed the way it is.

---

## The Three Core Abstractions

```
┌────────────────────────────────────────────────────────┐
│  Container / World                                     │
│  ┌─────────────────────┐  ┌─────────────────────────┐  │
│  │  Agent              │  │  Agent                  │  │
│  │  ┌───────────────┐  │  │  ┌──────────────────┐  │  │
│  │  │  Role A       │  │  │  │  Role B          │  │  │
│  │  └───────────────┘  │  │  └──────────────────┘  │  │
│  │  ┌───────────────┐  │  │  ┌──────────────────┐  │  │
│  │  │  Role B       │  │  │  │  Role C          │  │  │
│  │  └───────────────┘  │  │  └──────────────────┘  │  │
│  └─────────────────────┘  └─────────────────────────┘  │
│         ↑ messages ↓                ↑ messages ↓        │
│                 Container routes messages               │
└────────────────────────────────────────────────────────┘
```

```@raw html
<div class="mango-concept-grid">
  <div class="mango-concept-card">
    <span class="mango-concept-label">Core abstraction</span>
    <h4>Agent</h4>
    <p>Autonomous entity defined with <code>@agent</code>. Sends messages, schedules tasks, identified by an AID.</p>
  </div>
  <div class="mango-concept-card">
    <span class="mango-concept-label">Behavior unit</span>
    <h4>Role</h4>
    <p>Reusable behavior defined with <code>@role</code>. Multiple roles compose into one agent, sharing its address.</p>
  </div>
  <div class="mango-concept-card">
    <span class="mango-concept-label">Message router</span>
    <h4>Container / World</h4>
    <p>Routes messages between agents via TCP, MQTT, or a virtual simulation clock.</p>
  </div>
</div>
```

### Agent Structs

An **agent** is an autonomous entity that can send and receive messages and schedule tasks. It is defined with the `@agent` macro, which adds the necessary baseline fields to a plain Julia struct. Agents are identified by their *agent ID* (AID).

```julia
@agent struct MyAgent
    my_field::String
end

agent = MyAgent("hello")
aid(agent)        # → "agent0" (assigned at registration)
address(agent)    # → AgentAddress(aid="agent0", ...)
```

Agents respond to messages by defining `handle_message`, and they can proactively schedule tasks using `schedule`.

### Role Structs

A **role** encapsulates a reusable piece of agent behavior. An agent can have any number of roles; all roles share the same AID and address as their parent agent, because they are *part of* the agent, not independent entities.

Define a role with the `@role` macro:

```julia
@role struct LoggingRole
    log::Vector{String}
end

function Mango.handle_message(role::LoggingRole, message::Any, ::AbstractDict)
    push!(role.log, string(message))
end
```

Compose an agent from roles using `agent_composed_of`:

```julia
agent = agent_composed_of(LoggingRole(String[]))
```

Access a role on a running agent by type:

```julia
agent[LoggingRole].log
```

Roles are the preferred unit of reuse in Mango.jl. Rather than inheriting from a base agent type, compose agents from small, focused roles.

### Containers

A **container** is the message router. Every agent must be registered in a container. The container:
- Assigns an AID to each agent
- Routes incoming messages to the correct agent by AID
- Manages the protocol (TCP, MQTT, or simulation) for sending/receiving messages

```julia
container = create_tcp_container("127.0.0.1", 5555)
agent = register(container, MyAgent("hello"))
```

---

## Real-Time vs. Simulation

Mango.jl provides two container types that implement the same interface:

| | **Container** (real-time) | **World** (simulation) |
|---|---|---|
| Time | System clock, tasks run immediately | Virtual clock, controlled by `step_simulation` |
| Communication | TCP or MQTT protocol | Internal queue, delivery via `SimpleCommunicationSimulation` |
| Entry point | `activate(containers) do ... end` | `step_simulation(world, step_size_s)` |
| Use case | Production systems, hardware-in-the-loop | Rapid prototyping, testing, analysis |

Because both types implement `ContainerInterface`, the same agent and role code works in either context without modification.

---

## The Container Lifecycle

Starting and stopping containers manually is error-prone. The recommended pattern is `activate`, which starts the containers, runs your code, and shuts everything down — even on error.

```julia
# Single container
activate(container) do
    send_message(agent, "start", address(other_agent))
    sleep_until(() -> other_agent.counter >= 5)
end

# Multiple containers (started in parallel)
activate([container1, container2]) do
    # ...
end
```

For the simulation world, use `activate` the same way:

```julia
activate(world) do
    # setup: send initial messages, register recordings, etc.
    step_simulation(world, 1.0)
end
```

!!! note "Why activate?"
    `activate` guarantees that `shutdown` is always called, preventing resource leaks from forgotten teardown or errors mid-run. It also calls `notify_ready` on all agents, triggering `on_ready` lifecycle hooks.

---

## Message Flow

When `send_message(agent, content, address)` is called:

1. The message is serialized (if a codec is configured) and placed in the container's outgoing queue.
2. For **local** delivery (same container): the container dispatches it directly to the target agent's `handle_message`.
3. For **remote** delivery (TCP/MQTT): the protocol layer sends it over the network; on the receiving side, the container deserializes and dispatches it.
4. In **simulation**: the message is held in a queue; during the next `step_simulation` call the communication simulator determines the delivery time and the message is dispatched when the simulated clock reaches that time.

Message metadata (`meta` dict) carries auxiliary information such as sender AID, sender address, and tracking IDs.

---

## Task Scheduling

Agents and roles can schedule work using `schedule(agent, TaskData()) do ... end`. Tasks run concurrently (via Julia tasks / green threads). In real-time mode they execute immediately; in simulation mode the scheduler integrates with the virtual clock.

```julia
# Run once, right now
schedule(agent, InstantTaskData()) do
    println("immediate")
end

# Run every 5 seconds
schedule(agent, PeriodicTaskData(5.0)) do
    println("tick")
end
```

See the [Scheduling](@ref) reference for all task types.

---

## Simulation: Clock and Stepping

The simulation `World` maintains a `Clock` that records the current simulated `DateTime`. Time only advances when you call `step_simulation`.

- **Continuous mode**: you choose the step size; every task/message up to `t + step_size_s` is processed.
- **Discrete-event mode**: the simulation jumps to the time of the next scheduled task or incoming message.

```
t=0 ──▶ step(1s) ──▶ t=1 ──▶ step(1s) ──▶ t=2 ──▶ ...  (continuous)
t=0 ──▶ step()   ──▶ t=0.3 ──▶ step() ──▶ t=1.1 ──▶ ... (discrete-event)
```

See [Simulation](@ref) for the full API.
