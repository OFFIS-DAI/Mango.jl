# Getting Started with Mango.jl

This page gets you to a working agent system in the shortest possible path using the **express API**. For a step-by-step explanation of every concept involved, see the [Tutorial: Ping-Pong with TCP](@ref).

---

## Installation

```julia
using Pkg
Pkg.add("Mango")
```

---

## Quickstart — Two Agents Talking

The fastest way to run a Mango.jl system is with the express API. The example below creates two agents composed of roles and sends a message between them over TCP.

```julia
using Mango

@role struct PrintingRole
    out::Any = ""
end

function Mango.handle_message(role::PrintingRole, msg::Any, ::AbstractDict)
    role.out = msg
end

sender   = agent_composed_of(PrintingRole())
receiver = agent_composed_of(PrintingRole(), PrintingRole())

run_with_tcp(2, sender, receiver) do container_list
    wait(send_message(sender, "Ping", address(receiver)))
    sleep_until(() -> receiver[1].out == "Ping")
end

receiver[1].out  # "Ping"
```

!!! tip "What is run_with_tcp?"
    `run_with_tcp(n, agents...) do ... end` creates `n` TCP containers, distributes the agents round-robin, activates them, runs the block, and shuts everything down — even on error.

---

## Key Patterns at a Glance

### Define an agent

```julia
@agent struct MyAgent
    value::Int
end
```

### Handle incoming messages

```julia
function Mango.handle_message(agent::MyAgent, message::Any, meta::Any)
    println("Got: $message")
    reply_to(agent, "acknowledged", meta)  # reply to sender
end
```

### Send a message

```julia
send_message(agent, "hello", address(other_agent))
```

### Schedule a periodic task

```julia
schedule(agent, PeriodicTaskData(1.0)) do
    println("periodic tick")
end
```

---

## Choosing an Execution Mode

Every Mango.jl system uses **either** a real-time Container **or** a simulation World — not both. The same agent and role definitions work in either mode.

### Real-time mode (TCP/MQTT)

Agents communicate over the network. Time is the system clock.

```julia
container = create_tcp_container("127.0.0.1", 5555)
a1 = register(container, MyAgent(0))

activate(container) do
    send_message(a1, "hello", address(a1))
    sleep_until(() -> a1.value > 0)
end
```

### Simulation mode (no network required)

Agents communicate in-process. Time advances only when you call `step_simulation`.

```julia
using Dates

world = create_world(DateTime(2020))
a1 = register(world, MyAgent(0))

activate(world) do
    step_simulation(world, 1.0)   # advance 1 simulated second
end
```

!!! tip "Easy transition from simulation to real-time environment"
    Write your agent logic once. Transitioning the agent-based simulation is easily possible, often without changing the agent code at all.

---

## What to Read Next

```@raw html
<div class="mango-nav-grid">
  <a class="mango-nav-card" href="../concepts/">
    <strong>Concepts</strong>
    <span>Understand the architecture design.</span>
  </a>
  <a class="mango-nav-card" href="../tutorials/ping_pong/">
    <strong>Tutorial: Ping-Pong</strong>
    <span>Step-by-step TCP walkthrough.</span>
  </a>
  <a class="mango-nav-card" href="../role/">
    <strong>Roles</strong>
    <span>Structure behavior with roles.</span>
  </a>
  <a class="mango-nav-card" href="../container/">
    <strong>Container</strong>
    <span>TCP and MQTT container setup.</span>
  </a>
  <a class="mango-nav-card" href="../simulation/">
    <strong>Simulation</strong>
    <span>Run simulations with a virtual clock.</span>
  </a>
  <a class="mango-nav-card" href="../scheduling/">
    <strong>Scheduling</strong>
    <span>Schedule periodic and delayed tasks.</span>
  </a>
</div>
```
