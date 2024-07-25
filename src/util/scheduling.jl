export TaskData,
    PeriodicTaskData,
    InstantTaskData,
    DateTimeTaskData,
    AwaitableTaskData,
    ConditionalTaskData,
    execute_task,
    stop_task,
    stop_all_tasks,
    wait_for_all_tasks,
    stop_and_wait_for_all_tasks,
    schedule,
    Scheduler,
    AbstractScheduler,
    Clock

using Dates
using ConcurrentCollections

import Base.schedule, Base.sleep, Base.wait

abstract type AbstractClock end

@kwdef mutable struct Clock <: AbstractClock
    simulation_time::DateTime
end

struct DateTimeClock <: AbstractClock
end

struct Stop end
struct Continue end

abstract type TaskData end
abstract type AbstractScheduler end

function now(scheduler::AbstractScheduler)
    return DateTime.now()
end

function sleep(scheduler::AbstractScheduler, time_s::Real)
    return sleep(time_s)
end

function wait(scheduler::AbstractScheduler, timer::Timer, delay_s::Real)
    return wait(timer)
end

function clock(scheduler::AbstractScheduler)
    throw("unimplemented")
end
function tasks(scheduler::AbstractScheduler)
    throw("unimplemented")
end
    
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

mutable struct PeriodicTaskData <: TaskData
    interval_s::Real
    timer::Timer

    function PeriodicTaskData(interval_s::Real)
        return new(interval_s, Timer(interval_s; interval=interval_s))
    end
end

function is_stopable(data::PeriodicTaskData)::Bool
    return true
end

function stop_single_task(data::PeriodicTaskData)::Nothing
    close(data.timer)
end

struct InstantTaskData <: TaskData end

struct DateTimeTaskData <: TaskData
    date::Dates.DateTime
end

struct AwaitableTaskData <: TaskData
    awaitable::Any
end

struct ConditionalTaskData <: TaskData
    condition::Function
    check_interval_s::Float64
end

function execute_task(f::Function, scheduler::AbstractScheduler, data::PeriodicTaskData)
    while true
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

function schedule(f::Function, scheduler::AbstractScheduler, data::TaskData)
    task = Threads.@spawn execute_task(f, scheduler, data)
    tasks(scheduler)[task] = data
    return task
end

function stop_task(scheduler::AbstractScheduler, t::Task)
    data = tasks(scheduler)[t]

    if is_stopable(data)
        stop_single_task(data)
    end

    @warn "Attempted to stop a non-stopable task."
    return nothing
end

function stop_all_tasks(scheduler::AbstractScheduler)
    for data in values(tasks(scheduler))
        if is_stopable(data)
            stop_single_task(data)
        end
    end
end

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

function stop_and_wait_for_all_tasks(scheduler::AbstractScheduler)
    stop_all_tasks(scheduler)
    wait_for_all_tasks(scheduler)
end

