export TaskData,
    PeriodicTaskData,
    InstantTaskData,
    DateTimeTaskData,
    AwaitableTaskData,
    ConditionalTaskData,
    stop_task,
    stop_all_tasks,
    wait_for_all_tasks,
    stop_and_wait_for_all_tasks,
    schedule,
    Clock,
    Scheduler,
    SimulationScheduler

using Dates
using ConcurrentCollections

import Base.schedule, Base.sleep, Base.wait

"""
Abstract type of a clock, which holds the time of a simulation
"""
abstract type AbstractClock end

"""
Default clock implementation, in which a static DateTime field is used.
"""
@kwdef mutable struct Clock <: AbstractClock
    simulation_time::DateTime
end

"""
Clock implmentation using the real time and therefore not holding any time information
"""
struct DateTimeClock <: AbstractClock
end

struct Stop end
struct Continue end

"""
TaskData type, which is the supertype for all data structs, 
which shall describe a specific task type. Together with
a new method execute task for the inherting struct, new types
of tasks can be introduced.

# Example
```julia
struct InstantTaskData <: TaskData end
function execute_task(f::Function, scheduler::AbstractScheduler, data::InstantTaskData)
    f()
end
```
"""
abstract type TaskData end

"""
Abstract type for a scheduler
"""
abstract type AbstractScheduler end

"""
    now(scheduler::AbstractScheduler)

Internal, return the time on which the scheduler is working on
"""
function now(scheduler::AbstractScheduler)
    return DateTime.now()
end

"""
    sleep(scheduler::AbstractScheduler, time_s::Real)

Sleep for `time_s`. The way how the sleep is performed is determined
by the type of scheduler used.
"""
function sleep(scheduler::AbstractScheduler, time_s::Real)
    return sleep(time_s)
end

"""
    wait(scheduler::AbstractScheduler, timer::Timer, delay_s::Real)

Wait for `timer`.
"""
function wait(scheduler::AbstractScheduler, timer::Timer, delay_s::Real)
    return wait(timer)
end

"""
    clock(scheduler::AbstractScheduler)

Return the internal time representation, the `clock`.
"""
function clock(scheduler::AbstractScheduler)::AbstractClock
    throw("unimplemented")
end
"""
    tasks(scheduler::AbstractScheduler)

Return the tasks currently on schedule and managed by the scheduler.
"""
function tasks(scheduler::AbstractScheduler)
    throw("unimplemented")
end

"""
Default scheduler for the real time applications of Mango.jl.
"""
@kwdef struct Scheduler <: AbstractScheduler
    tasks::AbstractDict{Task,TaskData} = ConcurrentDict{Task,TaskData}()
    clock::DateTimeClock = DateTimeClock()
end

function clock(scheduler::Scheduler)
    return scheduler.clock
end
function tasks(scheduler::Scheduler)
    return scheduler.tasks
end

function is_stopable(data::TaskData)::Bool
    return false
end

function stop_single_task(data::TaskData)::Nothing
end

"""
Task data describing a periodic task. 

A periodic task is defined by an `interval_s` and optionally by a `condition`. The
interval determines how long the delay is between the recurring action. The condition
is a stopping condition (no argument) which shall return true if the task shall stop. 
"""
mutable struct PeriodicTaskData <: TaskData
    interval_s::Real
    condition::Function
    timer::Timer

    function PeriodicTaskData(interval_s::Real, condition::Function=() -> true)
        return new(interval_s, condition, Timer(interval_s; interval=interval_s))
    end
end

function is_stopable(data::PeriodicTaskData)::Bool
    return true
end

function stop_single_task(data::PeriodicTaskData)::Nothing
    close(data.timer)
end

"""
Instant task data. Functions scheduled with this data is scheduled instantly.
"""
struct InstantTaskData <: TaskData end

"""
Schedule the function at a specific time determined by the date::DateTime.
"""
struct DateTimeTaskData <: TaskData
    date::Dates.DateTime
end

"""
Schedule the function when the given `awaitable` is finished. Can be used 
with any type for which `wait` is defined.
"""
struct AwaitableTaskData <: TaskData
    awaitable::Any
end

"""
Schedule the function when the `condition` is fulfilled. To check whether it is fulfilled
the condition function is called every `check_interval_s`.
"""
struct ConditionalTaskData <: TaskData
    condition::Function
    check_interval_s::Float64
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::PeriodicTaskData)
    while data.condition()
        f()
        wait(scheduler, data.timer, data.interval_s)
    end
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::InstantTaskData)
    f()
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::DateTimeTaskData)
    sleep(scheduler, (data.date - Dates.now()).value / 1000)
    f()
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::AwaitableTaskData)
    wait(data.awaitable)
    f()
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::ConditionalTaskData)
    while !data.condition()
        sleep(scheduler, data.check_interval_s)
    end
    f()
end

"""
    schedule(f::Function, scheduler, data::TaskData)

Schedule a function (no arguments) using the specific scheduler (mostly the agent scheduler). The 
functino `f` is scheduled using the information in `data`, which specifies the way `f` will be 
scheduled.
"""
function schedule(f::Function, scheduler::AbstractScheduler, data::TaskData)
    task = Threads.@spawn execute_task(f, scheduler, data)
    tasks(scheduler)[task] = data
    return task
end

"""
    stop_task(scheduler::AbstractScheduler, t::Task)

Stop the task `t` managed by `scheduler`. This only works if the task has been scheduled
with the scheduler using a stoppable TaskData.
"""
function stop_task(scheduler::AbstractScheduler, t::Task)
    data = tasks(scheduler)[t]

    if is_stopable(data)
        stop_single_task(data)
    end

    @warn "Attempted to stop a non-stopable task."
    return nothing
end

"""
    stop_all_tasks(scheduler::AbstractScheduler)

Stopps all stoppable tasks managed by `scheduler`.
"""
function stop_all_tasks(scheduler::AbstractScheduler)
    for data in values(tasks(scheduler))
        if is_stopable(data)
            stop_single_task(data)
        end
    end
end

"""
    wait_for_all_tasks(scheduler::AbstractScheduler)

Wait for all tasks managed by `scheduler`.
"""
function wait_for_all_tasks(scheduler::AbstractScheduler)
    for task in keys(tasks(scheduler))
        try
            wait(task)
        catch err
            if isa(task.result, InterruptException) || isa(task.result, EOFError)
                # ignore, task has been interrupted by the scheduler
            else
                @error "An error occurred while waiting for $task" exception =
                    (err, catch_backtrace())
            end
        end
    end
end


"""
    stop_and_wait_for_all_tasks(scheduler::AbstractScheduler)

Stopps all stoppable tasks and then wait for all tasks in `scheduler`.
"""
function stop_and_wait_for_all_tasks(scheduler::AbstractScheduler)
    stop_all_tasks(scheduler)
    wait_for_all_tasks(scheduler)
end

