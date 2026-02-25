# Simulation

The simulation system in Mango.jl lets you run agent-based simulations with full control over time advancement, message delivery, and agent behavior.

!!! note "This page covers simulation mode only"
    A Mango.jl system uses either a simulation **World** (this page) or a real-time **[`Container`](@ref)** (TCP/MQTT) — not both. The `World` replaces the container entirely: it has no network, advances a virtual clock, and delivers messages through an in-process queue. Because both implement the same `ContainerInterface`, your agent code works unchanged in either mode. See [Real-Time Container](@ref) for details.

!!! tip "Background reading"
    For a conceptual overview of how the simulation world fits into the broader architecture, see [Mango.jl Concepts](@ref).

## Creating a World

Use `create_world` to set up a simulation. It initializes the clock, a communication simulator, a task simulator, and an optional space and behavior for the environment.

```@example sim_basic
using Mango, Dates

@agent struct SimAgent
end

# Create a world with simulation time starting at a given DateTime
comm_sim = SimpleCommunicationSimulation(default_delay_s=0)
world = create_world(DateTime(2020, 1, 1), communication_sim=comm_sim)

agent1 = register(world, SimAgent())
agent2 = register(world, SimAgent())

# Messages sent before stepping are queued and delivered during the step
send_message(agent2, "Hello!", AgentAddress(aid=aid(agent1)))

# Advance simulation by 1 second; the message is delivered within this step
result = step_simulation(world, 1)

@info result.time_elapsed
@info world.clock
```

You can also assign a custom agent ID when registering:

```julia
agent = register(world, SimAgent(), "my-agent-id")
```

Access registered agents by index or ID:

```julia
world[1]           # first registered agent
world["agent0"]    # agent with ID "agent0"
```

## Stepping the Simulation

### Continuous stepping

In continuous mode you choose a fixed time step in seconds. Every task and message scheduled within `[t, t + step_size_s)` is processed in order.

```julia
result = step_simulation(world, 1.0)   # advance 1 second
result = step_simulation(world, 0.5)   # advance 0.5 seconds
```

### Discrete event stepping

In discrete event mode the simulation automatically jumps to the time of the next scheduled task or incoming message, with no fixed step size needed. Call `step_simulation` without a second argument (or pass `-1`):

```julia
result = step_simulation(world)   # jump to next event
```

Returns `nothing` when there are no more events to process.

### Running until a time limit

`discrete_step_until` repeatedly calls `step_simulation` in discrete event mode until the simulation clock has advanced by the given number of seconds (or `Dates.Period`):

```julia
discrete_step_until(world, 100.0)         # run for 100 simulated seconds
discrete_step_until(world, Second(100))   # same with a Period
```

### Stepping until a condition is met

`step_until` advances the simulation until a predicate on the world becomes `true`, a maximum simulated time is reached, or no further events are available. It returns the number of steps taken.

```julia
# Run until agent is done, but no more than 60 simulated seconds
steps = step_until(world, w -> w[1].done; max_advance_s=60.0, step_size_s=1.0)

# Discrete-event mode (default): jump to each event in turn
steps = step_until(world, w -> length(w.recorded_messages) >= 10)
```

| Keyword | Default | Description |
|---|---|---|
| `max_advance_s` | `Inf` | Stop after this many simulated seconds even if condition is not met |
| `step_size_s` | `DISCRETE_EVENT` | Fixed step size; pass `DISCRETE_EVENT` for event-driven stepping |

### Mixing styles

Continuous and discrete stepping can be freely mixed within a single simulation run.

### The SimulationResult

Every successful `step_simulation` call returns a `SimulationResult`:

| Field | Description |
|---|---|
| `time_elapsed` | Wall-clock time the step took |
| `simulation_step_size_s` | The simulated time that was advanced |
| `messaging_result` | Details of message delivery iterations |
| `task_result` | Details of task execution iterations |

## Communication Simulation

The communication simulator controls message delivery delays and packet loss. Pass it to `create_world` via the `communication_sim` keyword.

### SimpleCommunicationSimulation

The default simulator uses a static global delay and an optional per-link delay dictionary.

```@example sim_comm
using Mango, Dates

@agent struct CommAgent
    received::Int
end

import Mango.handle_message
function handle_message(agent::CommAgent, ::Any, ::AbstractDict)
    agent.received += 1
end

comm_sim = SimpleCommunicationSimulation(
    default_delay_s = 1.0,   # 1 second delay for all links by default
    loss_percent = 0.0,       # no packet loss
)
world = create_world(DateTime(0), communication_sim=comm_sim)

a1 = register(world, CommAgent(0))
a2 = register(world, CommAgent(0))

# Override delay on a specific directed link (sender_id, receiver_id)
comm_sim.delay_s_directed_edge_dict[(aid(a1), aid(a2))] = 0.5

send_message(a1, "fast", AgentAddress(aid=aid(a2)))  # arrives after 0.5 s
send_message(a2, "slow", AgentAddress(aid=aid(a1)))  # arrives after 1.0 s

step_simulation(world, 0.6)   # only the fast message is delivered
@info a2.received   # 1
@info a1.received   # 0

step_simulation(world, 0.6)   # slow message is now delivered
@info a1.received   # 1
```

The sender ID is `nothing` when the message originates outside any registered agent (e.g. sent directly via `send_message(world.container, ...)`).

### DelayProviderCommunicationSimulation

For dynamic or stochastic delays, use `DelayProviderCommunicationSimulation`. Instead of fixed values it accepts provider functions that are called once per message to sample a delay.

```julia
using Distributions

provider = DelayProviderCommunicationSimulation(
    default_delay_s_provider = () -> rand(Exponential(0.5)),
)

# Per-link overrides also accept functions
provider.delay_s_directed_edge_dict[("agent0", "agent1")] = () -> rand(Uniform(0.1, 0.3))
```

### Distribution-based simulation from a topology graph

`create_distribution_based_com_sim` builds a `DelayProviderCommunicationSimulation` from a `MetaGraph` that encodes the network topology. Delays are sampled from a distribution (default: Poisson) scaled by the shortest path distance between agents.

```julia
using Graphs, MetaGraphsNext

topo = complete_topology(3)
auto_assign!(topo, world)
aid_graph = topology_to_aid_graph(topo)

comm_sim = create_distribution_based_com_sim(
    aid_graph,
    agents(world);
    base_delay_per_message_ms = 15,
    default_delay_per_edge_ms = 1,
    max_edge_delay_ms = 100,
)
world.communication_sim = comm_sim
```

### Custom communication simulator

Implement `CommunicationSimulation` and the `calculate_communication` method:

```julia
struct MyCommSim <: CommunicationSimulation
    delay_s::Real
end

function Mango.calculate_communication(
    sim::MyCommSim,
    clock::Clock,
    messages::Vector{MessagePackage},
)::CommunicationSimulationResult
    results = [PackageResult(true, sim.delay_s) for _ in messages]
    return CommunicationSimulationResult(results)
end

world = create_world(DateTime(0), communication_sim=MyCommSim(0.2))
```

`calculate_communication` may be called multiple times for the same set of messages within a single step (when new tasks produce new messages). Implementations must return the **same result** for the same `MessagePackage` object to keep the simulation consistent. Use the `message_cache` pattern from `SimpleCommunicationSimulation` if your delays involve randomness.

## Agent-Based Modeling with on_step

Beyond message-driven interaction, agents can react to each simulation step via the `on_step` hook. This enables agent-based modeling where agents continuously update their state.

```@example sim_abm
using Mango, Dates

import Mango.on_step

@agent struct MovingAgent
    speed::Float64
    x::Float64
end

function on_step(agent::MovingAgent, env::Environment, clock::Clock, step_size_s::Real)
    agent.x += agent.speed * step_size_s
end

world = create_world(DateTime(0))
a = register(world, MovingAgent(2.0, 0.0))

step_simulation(world, 1.0)
@info a.x   # 2.0

step_simulation(world, 0.5)
@info a.x   # 3.0
```

Roles also support `on_step`:

```julia
import Mango.on_step

@role struct CounterRole
    count::Int
end

function on_step(role::CounterRole, env::Environment, clock::Clock, step_size_s::Real)
    role.count += 1
end
```

`on_step` is called for every agent (and all their roles) before tasks and messages are processed within each step.

## Environment and Space

The `World` holds a `DefaultEnvironment` that provides a shared space agents can interact with. Access it via `env(world)` or `world.env`.

### Area2D space

The default space is `Area2D`, a 2D cartesian plane. Agents are assigned random positions on initialization. Use `location` to read and `move` to update an agent's position:

```@example sim_space
using Mango, Dates

import Mango.on_step

@agent struct SpaceAgent
    target::Position2D
end

function on_step(agent::SpaceAgent, env::Environment, clock::Clock, step_size_s::Real)
    current = location(env.space, agent)
    # move one step toward target
    move(env.space, agent, agent.target)
end

world = create_world(DateTime(0))
a = register(world, SpaceAgent(Position2D(5.0, 5.0)))

step_simulation(world, 1.0)
@info location(world.env.space, a)   # Position2D(5.0, 5.0)
```

A custom space can be created by:
1. Defining a `Position` subtype
2. Defining a `Space{YourPosition}` subtype
3. Implementing `initialize`, `move`, and `location` for it
4. Passing it to `create_world(space=MySpace(...))`

### Behavior

The environment can have a `Behavior` that is stepped alongside agents. This is useful for modeling external forces, environment dynamics, or global resource updates.

```julia
struct WeatherBehavior <: Behavior
    wind_speed::Float64
end

function Mango.on_step(b::WeatherBehavior, env::DefaultEnvironment, clock::Clock, step_size_s::Real)
    # update environment state or emit global events
    emit_global_event(env, :wind_changed)
end

world = create_world(DateTime(0), behavior=WeatherBehavior(3.5))
```

### Global events

`emit_global_event` broadcasts an event to every agent (and role) registered in the world. Agents and roles handle it via `on_global_event`:

```julia
function Mango.on_global_event(agent::MyAgent, clock::Clock, event::Symbol)
    if event == :wind_changed
        # react to the global event
    end
end
```

Similarly, `emit_agent_event` targets a single agent by its installed ID, which dispatches `on_agent_event` on that agent and its roles.

## Data Collection and Recording

The world provides a built-in data collection mechanism for recording time-series data during simulation runs. Recordings are set up before stepping and are updated automatically at the end of each step.

### Recording world-level data

`record_world!` records a scalar value at every step:

```@example sim_recording
using Mango, Dates

@agent struct RecAgent
    val::Int
end

import Mango.on_step
function on_step(agent::RecAgent, env::Environment, clock::Clock, step_size_s::Real)
    agent.val += 1
end

world = create_world(DateTime(0))
a1 = register(world, RecAgent(0))
a2 = register(world, RecAgent(0))

# Record the sum of all agent values at every step
record_world!(() -> sum(a.val for a in agents(world)), world, "total_val")

for _ in 1:5
    step_simulation(world, 1.0)
end

dc = data_collection(world, "total_val")
@info dc.time        # [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
@info dc.timeseries  # [0, 2, 4, 6, 8, 10]
```

### Recording per-agent data

`record_agent!` records a value per agent at every step:

```julia
record_agent!(agent -> agent.val, world, "agent_val")
```

After running the simulation, access the recording:

```julia
dc = data_agent_collection(world, "agent_val")
dc.timeseries  # Dict: aid => Vector of recorded values
dc.time        # shared time axis
```

### Recording agents with a specific role

`record_agent_having!` records only agents that have a particular role type, optionally filtered by `color` or a substring of the agent ID:

```julia
record_agent_having!(
    agent -> agent[MyRole].some_field,
    world,
    "role_data",
    MyRole;
    aid_contains = "sensor",   # only agents whose ID contains "sensor"
)
```

### Exporting recordings for plotting or CSV

```julia
# Plottable format: x (time), ys (matrix), labels (agent IDs)
x, ys, labels = agent_recording_as_plottable(world, "agent_val")

# CSV-compatible dict keyed by "key-agent_id"
d = agent_recordings_as_dict(world)
```

The `no_plot` and `dedicated_plots` keyword arguments let visualization extensions (e.g. `MangoPlotVisualization`) decide how to render the data.

### Message transaction recording

The world automatically records every delivered message as a `MessageTransaction`:

```julia
world.recorded_messages  # Vector{MessageTransaction}
```

Each entry has:

| Field | Description |
|---|---|
| `sender_id` | Aid of the sender (or `nothing` if sent externally) |
| `receiver_id` | Aid of the receiver |
| `sent_date` | `DateTime` when the message was sent |
| `arriving_date` | `DateTime` when the message was delivered |
| `content` | The message content |

Two helper functions make it easy to query the recorded messages without iterating manually:

```julia
# Filter by any combination of sender, receiver, and content type
txs = filter_messages(world; receiver_id=aid(agent_b))
txs = filter_messages(world; sender_id=aid(agent_a), content_type=PingMessage)

# Group all transactions by receiver AID
by_receiver = messages_as_dict(world)
msgs_for_b  = by_receiver[aid(agent_b)]
```

### Recording spatial positions

`record_position!` hooks into the data-collection infrastructure and records each agent's `Position2D` after every simulation step:

```julia
record_position!(world)                             # all positioned agents
record_position!(world; filter = a -> a isa EVAgent)  # filtered subset
record_position!(world, "my_key")                   # custom collection key
```

After stepping, inspect the history:

```julia
hist = position_history(world)           # AgentsRecording
hist.timeseries[aid(rover)]              # Vector{Position2D} — one entry per step
hist.time                                # Vector of elapsed seconds
```

### Position analytics

Four convenience functions compute movement statistics from a position history:

```julia
# Total path length (sum of step-to-step distances)
distance_traveled(world, rover)

# Straight-line distance between first and last recorded position
displacement(world, rover)

# distance_traveled / elapsed time
average_speed(world, rover)

# n×2 matrix with columns [x y], one row per snapshot
mat = trajectory_matrix(world, rover)
# mat[:, 1] → x-coordinates,  mat[:, 2] → y-coordinates
```

All four accept an optional third argument `key` (default `"positions"`) to target a named position collection.

## Express API

For simple simulations that do not require manual stepping, `run_in_simulation` provides a compact interface:

```@example sim_express
using Mango, Dates

@agent struct ExpressSimAgent end

results = run_in_simulation(5, ExpressSimAgent(), ExpressSimAgent(), start_time=DateTime(2020)) do world
    send_message(world[1], "hello", address(world[2]))
end
```

The first argument is the number of steps, followed by agent instances, an optional `start_time`, and a setup block that receives the world before stepping begins.

## Shutting Down

Call `shutdown(world)` after the simulation is complete to release internal resources:

```julia
shutdown(world)
```

!!! tip "Use activate for automatic shutdown"
    Just like with real-time containers, wrapping the simulation run in `activate(world) do ... end` ensures `shutdown` is called automatically even if an error occurs:
    ```julia
    activate(world) do
        record_agent!(a -> a.val, world, "values")
        discrete_step_until(world, 100.0)
    end
    ```
