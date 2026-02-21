# Agents

An **agent** is the fundamental unit of Mango.jl. It is an autonomous entity that can send and receive messages, schedule proactive tasks, and interact with a shared environment. Agents are identified by a unique *agent ID* (AID) assigned when they are registered in a container.

---

## Defining an Agent

Use the `@agent` macro to define an agent struct. It adds internal bookkeeping fields automatically; you only declare your application-specific fields:

```@example agent_def
using Mango

@agent struct CounterAgent
    count::Int
end

agent = CounterAgent(0)
```

!!! tip "Role-based composition"
    For reusable behavior, prefer composing agents from [`@role`](@ref) structs with [`agent_composed_of`](@ref). Use a plain `@agent` definition when the agent has behavior that does not need to be shared across agent types.

---

## Registering an Agent

Agents must be registered in a container before they can send or receive messages. Registration assigns an AID:

```julia
container = create_tcp_container("127.0.0.1", 5555)

agent = register(container, CounterAgent(0))        # AID auto-assigned: "agent0"
agent = register(container, CounterAgent(0), "c1")  # custom AID: "c1"

aid(agent)      # → "agent0" or "c1"
address(agent)  # → AgentAddress(...)
```

---

## Sending Messages

### Basic send

```julia
send_message(agent, "Hello!", address(other_agent))
```

The address can be an [`AgentAddress`](@ref) (for TCP/simulation) or an [`MQTTAddress`](@ref) (for MQTT).

### Message-sending variants

| Function | Description |
|---|---|
| [`send_message`](@ref) | Plain send |
| [`reply_to`](@ref) | Reply to the sender using the `meta` dict from `handle_message` |
| [`forward_to`](@ref) | Forward to a third agent, marking the message as forwarded |
| [`send_tracked_message`](@ref) | Send with a UUID tracking ID and an optional response handler |
| [`send_and_handle_answer`](@ref) | `send_tracked_message` with `do`-block syntax |
| `send_messages` | Send a batch in one call |
| `send_tracked_messages` | Send a tracked batch |
| `send_and_handle_answers` | Handle answers to a tracked batch |

### Tracked messages and responses

Use `send_tracked_message` when you want to automatically handle the response:

```julia
using Mango

@agent struct TrackingAgent end
@agent struct EchoAgent end

function Mango.handle_message(agent::EchoAgent, msg::Any, meta::Any)
    reply_to(agent, "echo: $msg", meta)
end

function on_response(::TrackingAgent, msg::Any, ::Any)
    @info "Got response" msg
end

run_with_tcp(1, TrackingAgent(), EchoAgent()) do cl
    wait(send_tracked_message(cl[1][1], "hello", address(cl[1][2]);
        response_handler=on_response))
    sleep(0.1)
end
```

`send_and_handle_answer` is the `do`-block variant:

```julia
wait(send_and_handle_answer(agent, "hello", address(other)) do agt, msg, meta
    @info "response" msg
end)
```

---

## Handling Messages

Override `handle_message` for your agent type:

```@example agent_handle
using Mango

@agent struct GreeterAgent
    greeted::Int
end

function Mango.handle_message(agent::GreeterAgent, ::Any, meta::Any)
    agent.greeted += 1
    reply_to(agent, "Hello back!", meta)
end
```

The `meta` dictionary carries auxiliary information:

| Key constant | Description |
|---|---|
| `SENDER_ID` | AID string of the sender |
| `SENDER_ADDR` | `AgentAddress` of the sender |
| `TRACKING_ID` | UUID string for tracked-message dialogs |

Use `sender_address(meta)` to extract the sender's `AgentAddress` directly.

---

## Message Forwarding Rules

An agent can automatically forward all messages from one address to another. This is useful for delegation and proxy patterns:

```julia
# Forward all messages that arrive from agent_a on to agent_b
add_forwarding_rule(my_agent, address(agent_a), address(agent_b), false)

# forward_replies=true also routes responses from agent_b back to agent_a
add_forwarding_rule(my_agent, address(agent_a), address(agent_b), true)

# Remove a rule
delete_forwarding_rule(my_agent, address(agent_a), address(agent_b))
```

---

## Scheduling Tasks

Agents can schedule asynchronous work. See [Scheduling](@ref) for all task types.

```@example agent_schedule
using Mango

@agent struct SchedulingAgent
    ticks::Int
end

agent = SchedulingAgent(0)

t = schedule(agent, InstantTaskData()) do
    agent.ticks += 1
end
wait(t)
```

Recurring tasks use `PeriodicTaskData`:

```julia
t = schedule(agent, PeriodicTaskData(0.5)) do
    agent.ticks += 1
end

sleep(2.0)
stop_task(agent, t)
wait_for_all_tasks(agent)
```

---

## Lifecycle Hooks

Implement these hooks to react to container lifecycle events:

| Hook | Called when |
|---|---|
| `on_start(agent)` | The container starts (before `notify_ready`) |
| `on_ready(agent)` | All containers are started and `notify_ready` has been called |

```julia
function Mango.on_ready(agent::MyAgent)
    # Send initial messages, start periodic tasks, etc.
    schedule(agent, PeriodicTaskData(1.0)) do
        send_message(agent, "heartbeat", address(coordinator))
    end
end
```

---

## Agent Descriptions

Every agent carries an `AgentDescription` with metadata you can use for categorization, color-coding, and filtering:

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | `String` | `""` | Human-readable label |
| `category` | `Symbol` | `:agent` | Logical category |
| `color` | `Symbol` | `:gray` | Tag for visualization / filtering |
| `uid` | `UUID` | auto | Universally unique identifier |

```julia
update_description(agent; name="coordinator", color=:blue, category=:control)

name(agent)      # → "coordinator"
color(agent)     # → :blue
category(agent)  # → :control
uid(agent)       # → UUID(...)
```

Agent descriptions integrate with `record_agent_having!` in simulation worlds for targeted data collection and with [`behavior_in`](@ref) for targeted behavior setup.

---

## Declarative Behavior with behavior_in

`behavior_in` lets you attach message handlers and event subscriptions to a matched subset of agents in a simulation world — without modifying any agent or role definition:

```julia
# All agents receive a handler for messages of type SomeMessage
behavior_in(world; on_message=SomeMessage) do agent, msg, meta
    @info "$(aid(agent)) got a SomeMessage"
end

# Only SensorAgent instances, handling a global event
behavior_in(world; agent_types=SensorAgent, on_global_event=AlarmEvent) do agent, event, clock
    @info "Sensor $(aid(agent)) alarm triggered"
end

# Only agents that have a CoordRole — handler called on the role
behavior_in(world; role_types=CoordRole, on_event=UpdateEvent) do role, event, clock
    role.count += 1
end
```

Matching criteria (all optional, combined with OR logic when agent-level, AND with role_types):

| Keyword | Matches agents that... |
|---|---|
| `agent_types` | are instances of one of these `DataType`s |
| `has_roles` | have any of these role types attached |
| `role_types` | have a role of one of these types (handler is called on the role) |
| `match_names` | have a matching `name` description field |
| `match_colors` | have a matching `color` description field |

---

## Role Management

Roles are added to an agent with [`add`](@ref), or all at once with [`agent_composed_of`](@ref):

```@example agent_roles
using Mango

@role struct GreetingRole end

@agent struct MyRoledAgent end

agent = MyRoledAgent()
add(agent, GreetingRole())

roles(agent)                    # → [GreetingRole()]
has_role(agent, GreetingRole)   # → true
agent[GreetingRole]             # access role by type
```

For details on role features, see [Roles](@ref).
