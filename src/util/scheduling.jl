
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
    Scheduler

import Dates
import Base.schedule
using ConcurrentCollections
using Parameters

struct Stop end
struct Continue end
abstract type TaskData end

@with_kw struct Scheduler
    tasks::AbstractDict{Task,TaskData} = ConcurrentDict{Task,TaskData}()
end

function is_stopable(data::TaskData)::Bool
    return false
end

function stop_single_task(data::TaskData)::Nothing
end

mutable struct PeriodicTaskData <: TaskData
    interval_s::Float64
    timer::Timer

    function PeriodicTaskData(interval_s::Float64)
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

function execute_task(f::Function, data::PeriodicTaskData)

    while true
        f()
        wait(data.timer)
    end
end

function execute_task(f::Function, data::InstantTaskData)
    f()
end

function execute_task(f::Function, data::DateTimeTaskData)
    sleep((data.date - Dates.now()).value / 1000)
    f()
end

function execute_task(f::Function, data::AwaitableTaskData)
    wait(data.awaitable)
    f()
end

function execute_task(f::Function, data::ConditionalTaskData)
    while !data.condition()
        sleep(data.check_interval_s)
    end
    f()
end

function schedule(f::Function, scheduler::Scheduler, data::TaskData)
    task = Threads.@spawn execute_task(f, data)
    scheduler.tasks[task] = data
    return task
end

function stop_task(scheduler::Scheduler, t::Task)
    data = scheduler.tasks[t]

    if is_stopable(data)
        stop_single_task(data)
    end

    @warn "Attempted to stop a non-stopable task."
    return nothing
end

function stop_all_tasks(scheduler::Scheduler)
    for data in values(scheduler.tasks)
        if is_stopable(data)
            stop_single_task(data)
        end
    end
end

function wait_for_all_tasks(scheduler::Scheduler)
    for task in keys(scheduler.tasks)
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

function stop_and_wait_for_all_tasks(scheduler::Scheduler)
    stop_all_tasks(scheduler)
    wait_for_all_tasks(scheduler)
end

