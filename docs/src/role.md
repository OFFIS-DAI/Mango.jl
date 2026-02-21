# Roles

A **role** encapsulates a reusable, self-contained piece of agent behavior. An agent can hold any number of roles; all roles share the parent agent's AID and address because they are logically *part of* the agent, not independent entities.

Roles are the preferred unit of code reuse in Mango.jl. Instead of deep inheritance hierarchies, you compose agents from small, focused role structs that can be freely combined and reused across agent types.

---

## Defining a Role

Use the `@role` macro — it adds the necessary internal fields (context, system handlers) to your struct:

```@example role_def
using Mango

@role struct LoggingRole
    messages::Vector{String}
end

role = LoggingRole(String[])
```

## Handling Messages

Override `handle_message` on a role type just as you would on an agent:

```@example role_handle
using Mango

@role struct CountingRole
    count::Int
end

function Mango.handle_message(role::CountingRole, ::Any, ::Any)
    role.count += 1
end
```

## Creating Agents from Roles

The preferred way to build agents is with `agent_composed_of`, which creates a lightweight wrapper agent that holds the given roles:

```@example role_compose
using Mango

@role struct RoleA end
@role struct RoleB end

# Creates a GeneralAgent internally and adds both roles
agent = agent_composed_of(RoleA(), RoleB())

agent[RoleA]          # access role by type
has_role(agent, RoleB) # → true
roles(agent)           # → [RoleA(), RoleB()]
```

To register directly into a container:

```@example role_add_container
using Mango

@role struct ServiceRole end

container = Container()
agent = add_agent_composed_of(container, ServiceRole())
```

To combine roles with a custom `@agent` base struct (for fields at the agent level):

```julia
@agent struct MyBaseAgent
    name::String
end

agent = agent_composed_of(RoleA(), RoleB(); base_agent=MyBaseAgent("main"))
```

---

## Role Lifecycle: setup

Override `setup` to run code when a role is attached to an agent. Use it to start tasks or subscribe to messages:

```@example role_setup
using Mango

@role struct TimerRole
    ticks::Int
end

function Mango.setup(role::TimerRole)
    schedule(role, PeriodicTaskData(1.0)) do
        role.ticks += 1
    end
end
```

`setup` is called inside `add(agent, role)`, so the role's context (and therefore its scheduler) is already available.

---

## Message Subscriptions

`subscribe_message` registers a predicate-based handler for incoming messages. The handler is only called when the predicate returns `true`:

```@example role_sub
using Mango

@role struct FilterRole
    important::Int
end

function Mango.setup(role::FilterRole)
    subscribe_message(role, (msg, _) -> msg isa String && startswith(msg, "ALERT")) do r, msg, _
        r.important += 1
        @debug "ALERT received" msg
    end
end
```

You can also listen for messages *sent outward* from the agent using `subscribe_send`:

```julia
function Mango.setup(role::AuditRole)
    subscribe_send(role, Returns(true)) do _, msg, _
        @info "Agent sent" msg
    end
end
```

---

## Inter-Role Communication

### Shared models

Roles within the same agent can share data through a **shared model** — a struct managed by the framework so every role sees the same instance.

Use the `@shared` annotation inside a `@role` definition:

```@example role_shared
using Mango

struct SharedCounter
    count::Ref{Int}
end
SharedCounter() = SharedCounter(Ref(0))

@role struct ProducerRole
    @shared
    counter::SharedCounter
end

@role struct ConsumerRole
    @shared
    counter::SharedCounter
end

agent = agent_composed_of(ProducerRole(), ConsumerRole())

# Both roles reference the same SharedCounter instance
agent[ProducerRole].counter.count[] += 1
agent[ConsumerRole].counter.count[]   # → 1
```

Or use `get_model` to retrieve the shared instance explicitly:

```julia
model = get_model(role, SharedCounter)
```

### Event system

Roles can communicate via events without coupling directly to each other.

**Emitting** an event from a role:

```@example role_event
using Mango

struct DataReady
    value::Float64
end

@role struct SensorRole end
@role struct ProcessorRole
    last::Float64
end

function Mango.handle_message(role::SensorRole, ::Any, ::Any)
    emit_event(role, DataReady(42.0))
end

function Mango.handle_event(role::ProcessorRole, ::Role, event::DataReady; event_type=nothing)
    role.last = event.value
end
```

**Subscribing** with a custom handler and optional filter condition:

```julia
function Mango.setup(role::ProcessorRole)
    subscribe_event(role, DataReady, (_, event) -> event.value > 0) do r, _, event, _
        r.last = event.value
    end
end
```

The `event_type` keyword in `handle_event` lets you use the same method for multiple event types by dispatching on `event_type` rather than the event struct.

---

## Sending from a Role

All message-sending functions available on agents also work on roles:

```julia
send_message(role, "hello", address(other_agent))
reply_to(role, "ack", meta)
schedule(role, InstantTaskData()) do
    send_message(role, "tick", address(coordinator))
end
```

The role's context provides transparent access to the parent agent's container, scheduler, and AID.

---

## Accessing Roles on an Agent

```julia
agent[MyRole]              # get role by type (error if not present)
has_role(agent, MyRole)    # check presence
roles(agent)               # all roles in registration order
```

When multiple roles of the same type are attached, `agent[MyRole]` returns the first one. Use `roles(agent)` and filter by type for the rest.
