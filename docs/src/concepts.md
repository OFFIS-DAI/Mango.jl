# Mango.jl Concepts

This page explains the core abstractions of Mango.jl and how they fit together. Reading it is not required to get started, but it will help you understand *why* the API is designed the way it is.

---

## The Three Core Abstractions

```
┌────────────────────────────────────────────────────────┐
│  Container (real-time)  ─── or ───  World (simulation) │
│       ↑ choose exactly one per system                  │
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
│                     routes messages                     │
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
    <span class="mango-concept-label">Execution mode — pick one</span>
    <h4>Container or World</h4>
    <p>Register agents in a real-time <strong>Container</strong> (TCP/MQTT) <em>or</em> a simulation <strong>World</strong> — not both. Agent code is identical either way.</p>
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

### Execution Backend: Container or World

Every agent must be registered in exactly one backend before it can communicate. There are two alternatives — you choose one for your entire system:

- **Container** — the real-time backend. Communicates over TCP or MQTT. Agents run on the system clock. Used for deployed systems, hardware-in-the-loop, and distributed setups.
- **World** — the simulation backend. No network involved. A virtual clock advances only when you call `step_simulation`. Used for prototyping, testing, and analysis.

```julia
# Real-time mode — register into a Container
container = create_tcp_container("127.0.0.1", 5555)
agent = register(container, MyAgent("hello"))

# Simulation mode — register into a World
using Dates
world = create_world(DateTime(2020))
agent = register(world, MyAgent("hello"))
```

!!! warning "Do not mix Container and World"
    A given agent system uses either a Container or a World — never both. Attempting to register the same agent in both is not supported. The value of the shared interface is code reuse across *separate* systems, not simultaneous use.

---

## Two Execution Modes

Mango.jl agent systems run in **exactly one** of two modes. You pick at the start by choosing which backend to register your agents in. The table below summarizes the difference:

| | **Container** (real-time) | **World** (simulation) |
|---|---|---|
| Backend | `create_tcp_container(...)` / `create_mqtt_container(...)` | `create_world(...)` |
| Time | System clock — tasks run as they are scheduled | Virtual clock — only advances via `step_simulation` |
| Communication | TCP or MQTT over the network | In-process queue, delivery controlled by a `CommunicationSimulation` |
| Entry point | `activate(container) do ... end` | `activate(world) do; step_simulation(world, Δt); end` |
| Use case | Production systems, hardware-in-the-loop | Rapid prototyping, testing, scalability analysis |

!!! note "Why the same agent code works in both"
    Container and World both implement the same `ContainerInterface`. Functions like `send_message`, `schedule`, `handle_message`, and `reply_to` behave identically in either mode. The typical workflow is to develop and test in simulation, then switch to a real-time container for deployment — without touching agent or role definitions.

---

## The Lifecycle Pattern

Regardless of which mode you use, the recommended way to start and stop is `activate`. It starts the backend, runs your code block, and shuts everything down — even on error.

**Real-time mode** (Container):

```julia
# One container
activate(container) do
    send_message(agent, "start", address(other_agent))
    sleep_until(() -> other_agent.counter >= 5)
end

# Multiple containers started in parallel
activate([container1, container2]) do
    send_message(ping_agent, "Ping", address(pong_agent))
    sleep_until(() -> ping_agent.counter >= 5)
end
```

**Simulation mode** (World):

```julia
activate(world) do
    # register recordings, send initial messages, then step
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
