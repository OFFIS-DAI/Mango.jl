# Tutorial: Ping-Pong in Simulation

This tutorial takes the same `PingPongAgent` from [Tutorial: Ping-Pong with TCP](@ref) and runs it in simulation mode. You will learn how to control virtual time, set message delivery delays, and collect time-series data — without any network or broker setup.

!!! tip "Read the TCP tutorial first"
    This tutorial is a direct continuation of [Tutorial: Ping-Pong with TCP](@ref). It assumes you are familiar with agents, `handle_message`, and `register`.

---

## Step 1 — The Same Agent Definition

Simulation mode requires **no change** to agent code. The `PingPongAgent` from the TCP tutorial is reused exactly:

```julia
using Mango, Dates

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
```

This is the core promise of Mango.jl: write agent logic once, run it anywhere.

---

## Step 2 — Create a World

Instead of containers, simulation mode uses a `World`. A `World` manages a virtual clock (a `DateTime`) that only advances when you call `step_simulation`. There is no network involved:

```julia
world = create_world(DateTime(2025, 1, 1))
```

The `DateTime` argument sets the starting point of the virtual clock.

---

## Step 3 — Register Agents

Agent registration uses exactly the same `register` call as with containers:

```julia
ping_agent = register(world, PingPongAgent(0))
pong_agent = register(world, PingPongAgent(0))
```

`address(agent)` works the same way and can be passed directly to `send_message`.

---

## Step 4 — Step the Simulation

With a real-time container you call `activate` and wait for wall-clock time to pass. In simulation mode you also use `activate`, but you advance time yourself with `step_simulation`:

```julia
activate(world) do
    # Queue the first message before any step
    send_message(ping_agent, "Ping", address(pong_agent))

    # Advance by 1 simulated second — queued messages are delivered in this step
    step_simulation(world, 1.0)
    println("t=1s  ping=$(ping_agent.counter) pong=$(pong_agent.counter)")

    # Keep stepping
    for _ in 1:9
        step_simulation(world, 1.0)
    end
    println("t=10s ping=$(ping_agent.counter) pong=$(pong_agent.counter)")
end
```

Each `step_simulation(world, Δt)` advances the virtual clock by `Δt` seconds and delivers all messages and tasks scheduled within that window.

!!! note "Default: zero delivery delay"
    `create_world` uses `SimpleCommunicationSimulation(default_delay_s=0)` by default, so every message is delivered in the same step it is sent. Step 5 shows how to add realistic delays.

---

## Step 5 — Controlling Message Delivery Delays

`SimpleCommunicationSimulation` lets you set how long messages take to arrive. This is independent of how long your agent code runs — it is purely a modeled network property:

```julia
comm_sim = SimpleCommunicationSimulation(default_delay_s=1.0)
world = create_world(DateTime(2025, 1, 1), communication_sim=comm_sim)

ping_agent = register(world, PingPongAgent(0))
pong_agent = register(world, PingPongAgent(0))

activate(world) do
    send_message(ping_agent, "Ping", address(pong_agent))

    step_simulation(world, 0.5)  # t = 0.5 s — message still in transit
    println("t=0.5s ping=$(ping_agent.counter) pong=$(pong_agent.counter)")
    # → ping=0 pong=0

    step_simulation(world, 0.6)  # t = 1.1 s — Ping arrives at pong_agent (sent at t=0, delay=1s)
    println("t=1.1s ping=$(ping_agent.counter) pong=$(pong_agent.counter)")
    # → ping=0 pong=1  (Pong reply now in flight, due at t=2.0)

    step_simulation(world, 1.0)  # t = 2.1 s — Pong arrives at ping_agent
    println("t=2.1s ping=$(ping_agent.counter) pong=$(pong_agent.counter)")
    # → ping=1 pong=1  (Ping reply now in flight, due at t=3.0)
end
```

You can also override the delay for a specific directed link:

```julia
# ping→pong: 0.1 s; pong→ping: still 1.0 s (default)
comm_sim.delay_s_directed_edge_dict[(aid(ping_agent), aid(pong_agent))] = 0.1
```

---

## Step 6 — Recording Data

The `World` has built-in time-series recording. Register a recording function before stepping; the framework calls it automatically at the end of every step:

```julia
comm_sim = SimpleCommunicationSimulation(default_delay_s=0.5)
world = create_world(DateTime(2025, 1, 1), communication_sim=comm_sim)

ping_agent = register(world, PingPongAgent(0))
pong_agent = register(world, PingPongAgent(0))

# Record each agent's counter value after every step
record_agent!(agent -> agent.counter, world, "counter")

activate(world) do
    send_message(ping_agent, "Ping", address(pong_agent))
    for _ in 1:10
        step_simulation(world, 1.0)
    end
end

dc = data_agent_collection(world, "counter")
println("Time axis:     ", dc.time)
println("Ping counters: ", dc.timeseries[aid(ping_agent)])
println("Pong counters: ", dc.timeseries[aid(pong_agent)])
```

`data_agent_collection` returns a struct with:

| Field | Content |
|---|---|
| `dc.time` | Shared time axis — one value per step |
| `dc.timeseries` | `Dict` mapping agent AID to a `Vector` of recorded values |

---

## Step 7 — Discrete Event Stepping

Fixed-size steps work well for continuous models. When agents only react to messages, **discrete event mode** is more efficient: the simulation jumps directly to the time of the next scheduled delivery, skipping empty intervals:

```julia
world = create_world(DateTime(2025, 1, 1),
    communication_sim=SimpleCommunicationSimulation(default_delay_s=0.5))

ping_agent = register(world, PingPongAgent(0))
pong_agent = register(world, PingPongAgent(0))

activate(world) do
    send_message(ping_agent, "Ping", address(pong_agent))
    discrete_step_until(world, 10.0)   # run until 10 simulated seconds have elapsed
end

println("Messages exchanged: ping=$(ping_agent.counter), pong=$(pong_agent.counter)")
println("Final clock: $(world.clock.simulation_time)")
```

`discrete_step_until(world, seconds)` repeatedly calls `step_simulation(world)` (no fixed step size) until the virtual clock has advanced by at least `seconds`. Each call jumps to the next event rather than advancing by a fixed delta.

---

## Step 8 — Express API

`run_in_simulation` handles world creation, registration, stepping, and shutdown in one call:

```julia
ping_agent = PingPongAgent(0)
pong_agent = PingPongAgent(0)

run_in_simulation(20, ping_agent, pong_agent,
        start_time=DateTime(2025, 1, 1)) do world
    send_message(ping_agent, "Ping", address(pong_agent))
end

println("Done: ping=$(ping_agent.counter), pong=$(pong_agent.counter)")
```

The first argument is the number of simulation steps. By default (`step_size_s=DISCRETE_EVENT`), each step jumps directly to the next scheduled event; pass `step_size_s=1` for fixed 1-second increments. The `do world` block runs before the first step, so the initial message is queued and delivered during step 1.

---

## Complete Standalone Script

```julia
using Mango, Dates

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

comm_sim = SimpleCommunicationSimulation(default_delay_s=0.5)
world = create_world(DateTime(2025, 1, 1), communication_sim=comm_sim)

ping_agent = register(world, PingPongAgent(0))
pong_agent = register(world, PingPongAgent(0))

record_agent!(agent -> agent.counter, world, "counter")

activate(world) do
    send_message(ping_agent, "Ping", address(pong_agent))
    discrete_step_until(world, 10.0)
end

dc = data_agent_collection(world, "counter")
println("Time:  ", dc.time)
println("Ping:  ", dc.timeseries[aid(ping_agent)])
println("Pong:  ", dc.timeseries[aid(pong_agent)])
```

---

## What's Next?

- **Agent-based modeling** with `on_step` and spatial environments — [Simulation](@ref)
- **Topology-based communication** — discover neighbors instead of hardcoding addresses — [Topology](@ref)
- **Schedule proactive tasks** inside a simulation — [Scheduling](@ref)
- **Deploy the same agent** over TCP — [Tutorial: Ping-Pong with TCP](@ref)
