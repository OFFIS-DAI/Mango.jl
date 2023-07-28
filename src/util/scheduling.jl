
export SchedulingType, ASYNC, PROCESS, THREAD, TaskData, PeriodicTaskData, InstantTaskData, DateTimeTaskData, AwaitableTaskData, ConditionalTaskData, execute_task, wait_for_all_tasks, schedule, Scheduler, interrupt, interrupt_all_tasks

import Dates
import Base.schedule
using Distributed: @spawnat, Future

"""
Internal scheduler for scheduling predefined task types
"""
struct Scheduler
    tasks::Vector{Union{Task,Future}}
end

Scheduler() = Scheduler(Vector())

@enum SchedulingType begin
    ASYNC = 1
    THREAD = 2
    PROCESS = 3
end

abstract type TaskData end

struct PeriodicTaskData <: TaskData
    interval_s::Float64
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
        sleep(data.interval_s)
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

function schedule(f::Function, scheduler::Scheduler, data::TaskData, scheduling_type::SchedulingType=ASYNC)
    task = nothing
    if scheduling_type == ASYNC
        task = @asynclog execute_task(f, data)
    elseif scheduling_type == THREAD
        task = Threads.@spawn execute_task(f, data)
    elseif scheduling_type == PROCESS
        task = @spawnat :any execute_task(f, data)
    end
    push!(scheduler.tasks, task)
    return task
end

function wait_for_all_tasks(scheduler::Scheduler)
    for task in scheduler.tasks
        try
            wait(task)
        catch err
            if isa(task.result, InterruptException)
                # ignore, task has been interrupted by the scheduler
            else
                @error "An error occurred while waiting for $task" exception=(err, catch_backtrace())
            end
        end
    end
end

function interrupt_all_tasks(scheduler::Scheduler)
    for task in scheduler.tasks
        interrupt(task)
    end
end

function interrupt(task::Any)
    @asynclog Base.throwto(task, InterruptException())
end

