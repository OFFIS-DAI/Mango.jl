# Scheduling

Mango.jl provides a built-in task scheduler so agents and roles can do work proactively — without waiting for an incoming message. Tasks are scheduled on an agent (or role) and run asynchronously. In simulation mode the same API integrates with the virtual clock, so tasks fire at the correct simulated time.

!!! note "Applies to both modes"
    The scheduling API (`schedule`, `stop_task`, `wait_for_all_tasks`, all `TaskData` types) works identically in real-time mode (Container) and simulation mode (World). The only exception is scheduling directly on the environment, which is simulation-only and marked as such in the section below.

---

## Task Types

| Type | When it runs | Key field |
|---|---|---|
| [`InstantTaskData`](@ref) | Immediately (next async iteration) | — |
| [`DelayTaskData`](@ref) | After a fixed delay | `delay_s::Real` |
| [`PeriodicTaskData`](@ref) | Repeatedly at a fixed interval | `period_s::Real` |
| [`DateTimeTaskData`](@ref) | At a specific `DateTime` | `date_time::DateTime` |
| [`AwaitableTaskData`](@ref) | When an awaitable object completes | `awaitable` |
| [`ConditionalTaskData`](@ref) | When a predicate becomes `true` | `condition::Function`, `period_s::Real` |
| [`TimeseriesTaskData`](@ref) | Once for each `DateTime` in a vector | `dates::Vector{DateTime}` |

---

## Scheduling a Task

Use `schedule(agent_or_role, TaskData()) do ... end`. It returns a `Task` that can be waited on:

```@example sched_instant
using Mango

@agent struct WorkAgent
    result::Int
end

agent = WorkAgent(0)

t = schedule(agent, InstantTaskData()) do
    agent.result = 42
end

wait(t)
agent.result  # → 42
```

### Delayed task

```@example sched_delay
using Mango

@agent struct DelayAgent
    fired::Bool
end

agent = DelayAgent(false)

t = schedule(agent, DelayTaskData(0.05)) do
    agent.fired = true
end

wait(t)
agent.fired  # → true
```

### Periodic task

Periodic tasks run indefinitely. Use `stop_task` to stop them and `wait_for_all_tasks` to wait for completion:

```@example sched_periodic
using Mango

@agent struct TickAgent
    ticks::Int
end

agent = TickAgent(0)

t = schedule(agent, PeriodicTaskData(0.05)) do
    agent.ticks += 1
end

sleep(0.18)
stop_task(agent, t)
wait_for_all_tasks(agent)
```

!!! warning "Waiting on periodic tasks blocks forever"
    Calling `wait(t)` on a periodic task will block indefinitely because it never finishes. Always call `stop_task` first, then `wait_for_all_tasks`.

### Stop all tasks at once

```@example sched_stop_all
using Mango

@agent struct MultiTaskAgent
    ticks::Int
end

agent = MultiTaskAgent(0)

for _ in 1:3
    schedule(agent, PeriodicTaskData(0.05)) do
        agent.ticks += 1
    end
end

sleep(0.1)
stop_all_tasks(agent)
wait_for_all_tasks(agent)
```

`stop_and_wait_for_all_tasks(agent)` combines the last two calls.

---

## Scheduling from a Role

All task functions work identically on roles:

```julia
function Mango.setup(role::HeartbeatRole)
    schedule(role, PeriodicTaskData(5.0)) do
        send_message(role, "heartbeat", address(coordinator))
    end
end
```

---

## Scheduling on the Environment

!!! note "Simulation mode only"
    The environment scheduler is part of the `World` and is only available in simulation mode.

In simulation mode, tasks can also be scheduled directly on the environment (useful for global timed events):

```julia
activate(world) do
    schedule(env(world), DelayTaskData(10.0)) do
        emit_global_event(world.env, :market_opens)
    end
end
```

---

## DateTime and Conditional Tasks

### DateTimeTaskData — run at a specific time

```julia
using Dates

target = DateTime(2025, 6, 1, 9, 0, 0)  # June 1st 09:00:00

schedule(agent, DateTimeTaskData(target)) do
    @info "Market opens" now()
end
```

In simulation mode, the task fires when the virtual clock reaches `target`.

### ConditionalTaskData — run when a predicate is true

```julia
schedule(agent, ConditionalTaskData(() -> agent.inbox_size > 0, 0.1)) do
    process_inbox(agent)
end
```

The scheduler re-evaluates the condition every `0.1` seconds (real time) or simulation steps.

### TimeseriesTaskData — run once per DateTime in a list

`TimeseriesTaskData` accepts a vector of `DateTime` values and calls the task function once for each of them in order.

!!! warning "The function receives the date as its argument"
    Unlike all other task types, the scheduled function for `TimeseriesTaskData` is called with the current `DateTime` as its first argument: `f(date::DateTime)`.

```julia
using Dates

dates = [DateTime(2025, 1, d) for d in 1:5]   # Jan 1–5

schedule(agent, TimeseriesTaskData(dates)) do date
    @info "Running at" date
end
```

In simulation mode the scheduler sleeps to the next date on the virtual clock between invocations. In real-time mode it sleeps the wall-clock difference.

---

## Task Control Reference

| Function | Description |
|---|---|
| `schedule(f, agent, data)` | Schedule `f` with the given `TaskData` |
| `stop_task(agent, t)` | Signal a task to stop after its current iteration |
| `stop_all_tasks(agent)` | Signal all stoppable tasks to stop |
| `wait_for_all_tasks(agent)` | Wait until all scheduled tasks have finished |
| `stop_and_wait_for_all_tasks(agent)` | Stop all tasks and wait |
