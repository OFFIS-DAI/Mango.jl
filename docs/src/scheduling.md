# Scheduling

The `Scheduling` module exports several types and functions to facilitate task scheduling and execution. Let's briefly review the main components of this module.

## Task Data Types

The module provides different [`TaskData`](@ref) types, each catering to specific scheduling requirements:

1. [`PeriodicTaskData`](@ref): For tasks that need to be executed periodically, it holds the time interval in seconds between task executions.
2. [`InstantTaskData`](@ref): For tasks that need to be executed instantly, without any delay.
3. [`DateTimeTaskData`](@ref): For tasks that need to be executed at a specific date and time.
4. [`AwaitableTaskData`](@ref): For tasks that require waiting for an awaitable object to complete before execution.
5. [`ConditionalTaskData`](@ref): For tasks that execute based on a specific condition at regular intervals.


## Typical usage

Typically the scheduler is used within methods from the agent. To schedule a task the function [`schedule`](@ref) can be used. It takes two inputs: The agent (which forwards the call to its scheduler) and the TaskData object of the task.

```julia
agent = MyAgent(0)
result = 0

schedule(agent, InstantTaskData()) do 
    # some expensive calculation
    result = 10       
end
wait_for_all_tasks(agent)
```

[`PeriodicTaskData`](@ref) creates tasks that get executed repeatedly forever. 
This means that calling `wait` on such a task will generally simply block forever.
For this reason a periodic task has to be stopped before it can be waited on.

```julia
delay_in_s = 0.5 # delay between executions of the task in seconds

t = schedule(agent, PeriodicTaskData(delay)) do 
    # some expensive calculation
    result = 10       
end

stop_task(agent, t)
wait_for_all_tasks(agent)
```

Alternatively, you can stop all `stopable` tasks simultaneously with the [`stop_all_tasks`](@ref) function.

```julia
delay_in_s = 0.5 # delay between executions of the task in seconds

for i in 1:100
    schedule(agent, PeriodicTaskData(delay)) do 
        # some expensive calculation
        result = 10       
    end
end

stop_all_task(agent, t)
wait_for_all_tasks(agent)
```

Finally, [`stop_and_wait_for_all_tasks`](@ref) is a convenience methods combining both [`stop_all_tasks`](@ref) and [`wait_for_all_tasks`](@ref).


## Scheduler

The [`Scheduler`](@ref) type is an internal structure that holds a collection of tasks to be scheduled and executed. Every agent contains such a scheduler struct by default and implements methods for convenient delegation.

```julia
struct Scheduler
    tasks::Vector{Task}
end
```

The [`execute_task`](@ref) function executes a task with a specific [`TaskData`](@ref).

```julia
execute_task(f::Function, data::PeriodicTaskData)
execute_task(f::Function, data::InstantTaskData)
execute_task(f::Function, data::DateTimeTaskData)
execute_task(f::Function, data::AwaitableTaskData)
execute_task(f::Function, data::ConditionalTaskData)
```

The [`schedule`](@ref) function adds a task to the scheduler with the specified [`TaskData`](@ref) and scheduling type.

```julia
schedule(f::Function, scheduler::Union{Scheduler,Agent}, data::TaskData, scheduling_type::SchedulingType=ASYNC)
```

The [`wait_for_all_tasks`](@ref) function waits for all the scheduled tasks in the provided scheduler to complete.

```julia
wait_for_all_tasks(scheduler::Scheduler)
```

The [`stop_task`](@ref) function sends the stop signal to a task `t`. This will result in its completion once the next execution cycle is finished. If `t` is not stopable this will output a warning.

```julia
stop_task(scheduler::Scheduler, t::Task)
```

The [`stop_all_tasks`](@ref) function sends the stop signal to all stopable tasks. This will result in their completion once the next execution cycle is finished.

```julia
stop_all_tasks(scheduler::Scheduler)
```

The [`stop_and_wait_for_all_tasks`](@ref) function sends the stop signal to all stopable tasks. It then waits for all scheduled tasks to finish.

```julia
stop_and_wait_for_all_tasks(scheduler::Scheduler)
```
