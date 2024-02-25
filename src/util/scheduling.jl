
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

struct Stop end
struct Continue end
abstract type TaskData end

struct Scheduler
    tasks::Dict{Task,TaskData}
end

Scheduler() = Scheduler(Dict{Task,TaskData}())

function is_stopable(data::TaskData)::Bool
    return false
end

struct PeriodicTaskData <: TaskData
    interval_s::Float64
    ch::Channel # channel for sending interrupt signal

    function PeriodicTaskData(interval_s::Float64)
        return new(interval_s, Channel(1))
    end
end

function is_stopable(data::PeriodicTaskData)::Bool
    return true
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
    signal = Continue()

    while true
        f()
        sleep(data.interval_s)

        # check stop condition
        if isready(data.ch)
            signal = take!(data.ch)
        end

        if signal == Stop()
            break
        end
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
        put!(data.ch, Stop())
    end

    @warn "Attempted to stop a non-stopable task."
    return nothing
end

function stop_all_tasks(scheduler::Scheduler)
    for data in values(scheduler.tasks)
        if is_stopable(data)
            put!(data.ch, Stop())
        end
    end
end

function wait_for_all_tasks(scheduler::Scheduler)
    for task in keys(scheduler.tasks)
        try
            wait(task)
        catch err
            if isa(task.result, InterruptException)
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

