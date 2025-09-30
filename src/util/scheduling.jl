export TaskData,
    PeriodicTaskData,
    InstantTaskData,
    DelayTaskData,
    DateTimeTaskData,
    AwaitableTaskData,
    ConditionalTaskData,
    stop_task,
    stop_all_tasks,
    wait_for_all_tasks,
    stop_and_wait_for_all_tasks,
    schedule,
    Clock,
    DateTimeClock,
    Scheduler,
    SimulationScheduler,
    AbstractScheduler,
    AbstractClock,
    sleep_until, 
    seconds_elapsed,
    tasks, 
    clock

using Dates
using ConcurrentCollections

import Base.schedule, Base.sleep, Base.wait, Base.notify

"""
Abstract type of a clock, which holds the time of a simulation
"""
abstract type AbstractClock end

function time(clock::AbstractClock)
    throw("Not defined!")
end
function seconds_elapsed(clock::AbstractClock)
    throw("Not defined!")
end

"""
Default clock implementation, in which a static DateTime field is used.
"""
@kwdef mutable struct Clock <: AbstractClock
    simulation_time::DateTime
    initial_time::DateTime
    function Clock(simulation_time)
        return new(simulation_time, simulation_time)
    end
end

"""
Clock implmentation using the real time and therefore not holding any time information
"""
struct DateTimeClock <: AbstractClock
end

function time(clock::Clock)
    return clock.simulation_time
end
function seconds_elapsed(clock::Clock)
    return (time(clock) - clock.initial_time).value / 1000
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
    return Dates.now()
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
    wait(scheduler::AbstractScheduler, awaitable::Any)

Wait on awaitable based on its schedulers policy.
"""
function wait(scheduler::AbstractScheduler, awaitable::Any)
    return wait(awaitable)
end

function notify(scheduler::AbstractScheduler, event::Threads.Event)
    return notify(event)
end

"""
    clock(scheduler::AbstractScheduler)

Return the internal time representation, the `clock`.
"""
function clock(scheduler::AbstractScheduler)::AbstractClock
    throw(InvalidStateException("unimplemented", :NotImplemented))
end
"""
    tasks(scheduler::AbstractScheduler)

Return the tasks currently on schedule and managed by the scheduler.
"""
function tasks(scheduler::AbstractScheduler)
    throw(InvalidStateException("unimplemented", :NotImplemented))
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
Delayed task data. Functions scheduleld with this data are delays by delay_s seconds
"""
struct DelayTaskData <: TaskData
    delay_s::Real
end

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
    wait(scheduler::AbstractScheduler, awaitable_task_data::AwaitableTaskData)

Wait for the awaitable data in `awaitable_task_data`.
"""
function wait(scheduler::AbstractScheduler, awaitable_task_data::AwaitableTaskData)
    return wait(awaitable_task_data.awaitable)
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

function execute_task(f::Function, scheduler::AbstractScheduler, data::DelayTaskData)
    sleep(scheduler, data.delay_s)
    f()
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::DateTimeTaskData)
    sleep(scheduler, (data.date - now(scheduler)).value / 1000)
    f()
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::AwaitableTaskData)
    wait(scheduler, data)
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
    task = @spawnlog execute_task(f, scheduler, data)
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
        return
    end

    @warn "Attempted to stop a non-stopable task."
    return
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

"""
    sleep_until(condition::Function)

Sleep until the condition (no args -> bool) is met.
"""
function sleep_until(condition::Function; interval_s::Real=0.01)
    while !condition()
        sleep(interval_s)
    end
end

### Simulation Scheduler


"""
Specific scheduler, defined to be injected to the agents and intercept scheduling 
calls and especially the sleep calls while scheduling. This struct manages all necessary times and
events fulfilling the purpose to step the tasks only for a given step_size.
"""
@kwdef struct SimulationScheduler <: AbstractScheduler
    clock::Clock
    events::ConcurrentDict{Task,Base.Event} = ConcurrentDict{Task,Base.Event}()
    task_time::ConcurrentDict{Task,DateTime} = ConcurrentDict{Task,DateTime}()
    tasks::ConcurrentDict{Task,Tuple{TaskData,Base.Event}} = ConcurrentDict{Task,Tuple{TaskData,Base.Event}}()
    queue::ConcurrentQueue{Union{Tuple{Function,TaskData,Base.Event},Task}} = ConcurrentQueue{Union{Tuple{Function,TaskData,Base.Event},Task}}()
    wait_queue::ConcurrentQueue{Task} = ConcurrentQueue{Task}()
end

"""
Internal struct, signaling the state of the tasks which has been waited on.
"""
struct WaitResult
    cont::Bool
    result::Any
end

function stop_and_wait_for_all_tasks(scheduler::SimulationScheduler)
    # do nothing, as task simulation will handle that part.
end

function determine_next_event_time_with(scheduler::SimulationScheduler, simulation_time::DateTime)
    lowest = nothing

    # normal queue
    next = scheduler.queue.head.next
    while !isnothing(next)
        if isa(next.value, Tuple)
            return 0
        else
            throw("This should not happen! Did you schedule a task with zero sleep time?")
        end
        next = next.next
    end

    # wait queue
    next = scheduler.wait_queue.head.next
    while !isnothing(next)
        t = scheduler.task_time[next.value]
        if isnothing(lowest) || t < lowest
            lowest = t
        end
        next = next.next
    end
    if isnothing(lowest)
        return nothing
    end
    return (lowest - simulation_time).value / 1000
end

function wait_for_finish_or_sleeping(scheduler::SimulationScheduler, task::Task, step_size_s::Real, timeout_s::Real=10, check_delay_s=0.001)::WaitResult
    remaining = timeout_s
    while remaining > 0
        if !istaskdone(task)
            if haskey(scheduler.events, task)
                event_time = scheduler.task_time[task]
                @debug "not done, found event" event_time add_seconds(scheduler.clock.simulation_time, step_size_s)
                if event_time <= add_seconds(scheduler.clock.simulation_time, step_size_s)
                    return WaitResult(true, nothing)
                else
                    return WaitResult(false, nothing)
                end
            end
        else
            return WaitResult(false, Some(task.result))
        end
        sleep(check_delay_s)
        remaining -= check_delay_s
    end
    throw("Simulation encountered a task timeout!")
end

function now(scheduler::SimulationScheduler)
    return scheduler.clock.simulation_time
end

function sleep(scheduler::SimulationScheduler, time_s::Real)
    event = Base.Event()
    ctime = scheduler.clock.simulation_time
    if haskey(scheduler.task_time, current_task())
        ctime = scheduler.task_time[current_task()]
    end
    scheduler.events[current_task()] = event
    scheduler.task_time[current_task()] = add_seconds(ctime, time_s)
    @debug "Sleep task with" current_task() event ctime time_s
    wait(event)
end

function wait(scheduler::SimulationScheduler, timer::Timer, delay_s::Real)
    sleep(scheduler, delay_s)
end

function wait(scheduler::SimulationScheduler, awaitable_task_data::AwaitableTaskData)
    elapsed = @elapsed wait(awaitable_task_data.awaitable)
    sleep(scheduler, elapsed)
end

function wait(scheduler::SimulationScheduler, event::Threads.Event)
    ctime = scheduler.clock.simulation_time
    if haskey(scheduler.task_time, current_task())
        ctime = scheduler.task_time[current_task()]
    end
    scheduler.events[current_task()] = event
    scheduler.task_time[current_task()] = DateTime(9999)
    return wait(event)
end

function notify(scheduler::SimulationScheduler, event::Threads.Event)
    maybepop!(scheduler.events, current_task())
    scheduler.task_time[current_task()] = DateTime(0)
    return Base.notify(event)
end

function tasks(scheduler::SimulationScheduler)
    return scheduler.tasks
end

clock(scheduler::SimulationScheduler) = scheduler.clock

function schedule(f::Function, scheduler::SimulationScheduler, data::TaskData)
    event = Base.Event()
    push!(scheduler.queue, (f, data, event))
    return event
end

function do_schedule(f::Function, scheduler::SimulationScheduler, data::TaskData, event::Base.Event)
    task = Threads.@spawn execute_task(f, scheduler, data)
    tasks(scheduler)[task] = (data, event)
    return task
end