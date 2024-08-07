export TaskIterationResult, TaskResult, TaskSimulation, create_agent_scheduler, step_iteration, SimulationScheduler, SimpleTaskSimulation

using UUIDs
using Dates
using ConcurrentCollections
using Bijections

# Interface Definition
struct TaskResult
    done::Bool
    finish_time::DateTime
    raw_result::Any
end

@kwdef mutable struct TaskIterationResult 
    task_to_result::Dict{UUID, TaskResult} = Dict()
    state_changed::Bool = false
end

abstract type TaskSimulation end

function create_agent_scheduler(task_sim::TaskSimulation)
    throw(ErrorException("Please implement create_agent_scheduler(...)"))
end
function step_iteration(task_sim::TaskSimulation, step_size_s::Real)::TaskIterationResult 
    throw(ErrorException("Please implement step_iteration(...)"))
end
function determine_next_event_time(task_sim::TaskSimulation)
    throw(ErrorException("Please implement determine_next_event_time(...)"))
end

# Scheduler Definition
@kwdef struct SimulationScheduler <: AbstractScheduler
    clock::Clock
    events::ConcurrentDict{Task,Tuple{Base.Event,DateTime}} = ConcurrentDict{Task,Tuple{Base.Event,DateTime}}()
    tasks::ConcurrentDict{Task,Tuple{TaskData,Base.Event}} = ConcurrentDict{Task,Tuple{TaskData,Base.Event}}()
    queue::ConcurrentQueue{Union{Tuple{Function,TaskData,Base.Event}, Task}} = ConcurrentQueue{Union{Tuple{Function,TaskData,Base.Event}, Task}}()
    wait_queue::ConcurrentQueue{Task} = ConcurrentQueue{Task}()
end

struct WaitResult
    cont::Bool
    result::Any
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
        t = scheduler.events[next.value][2]
        if isnothing(lowest) || t < lowest
            lowest = t
        end
        next = next.next
    end
    if isnothing(lowest)
        return nothing
    end
    return (lowest - simulation_time).value/1000
end

function wait_for_finish_or_sleeping(scheduler::SimulationScheduler, task::Task, step_size_s::Real, timeout_s::Real=10, check_delay_s=0.001)::WaitResult 
    remaining = timeout_s
    while remaining > 0
        sleep(check_delay_s)
        remaining -= check_delay_s
        if !istaskdone(task)
            if haskey(scheduler.events, task)
                event_time = scheduler.events[task]
                @debug "not done, found event" event_time[2] add_seconds(scheduler.clock.simulation_time, step_size_s)
                if event_time[2] <= add_seconds(scheduler.clock.simulation_time, step_size_s)
                    return WaitResult(true, nothing)
                else
                    return WaitResult(false, nothing)
                end
            end
        else
            return WaitResult(false, Some(task.result))
        end
    end
    throw("Simulation encountered a task timeout!")
end

function now(scheduler::SimulationScheduler)
    return scheduler.clock.simulation_time
end

function sleep(scheduler::SimulationScheduler, time_s::Real)
    event = Base.Event()
    ctime = scheduler.clock.simulation_time
    if haskey(scheduler.events, current_task())
        ctime = scheduler.events[current_task()][2]
    end
    scheduler.events[current_task()] = (event, add_seconds(ctime, time_s))
    @debug "Sleep task with" current_task() event add_seconds(ctime, time_s)
    wait(event)
end

function wait(scheduler::SimulationScheduler, timer::Timer, delay_s::Real)
    sleep(scheduler, delay_s)
end

function tasks(scheduler::SimulationScheduler)
    return scheduler.tasks
end

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

# Default Implementation of Interface
@kwdef mutable struct SimpleTaskSimulation <: TaskSimulation
    clock::Clock
    agent_schedulers::Vector{SimulationScheduler} = Vector{SimulationScheduler}()
end

function determine_next_event_time(task_sim::SimpleTaskSimulation)
    event_times = [determine_next_event_time_with(scheduler, task_sim.clock.simulation_time) for scheduler in task_sim.agent_schedulers]
    event_times = event_times[event_times.!=nothing]
    if length(event_times) <= 0
        return nothing
    end
    return findmin(event_times)[1]
end

function create_agent_scheduler(task_sim::SimpleTaskSimulation)
    scheduler = SimulationScheduler(clock=task_sim.clock)
    push!(task_sim.agent_schedulers, scheduler)
    return scheduler
end

function transfer_wait_queue(scheduler::SimulationScheduler)
    @debug "Transfer"
    while true
        next_task = maybepopfirst!(scheduler.wait_queue)
        if isnothing(next_task)
            break
        end 
        push!(scheduler.queue, something(next_task))
    end
end

function step_iteration(task_sim::SimpleTaskSimulation, step_size_s::Real, first_step=false)::TaskIterationResult 
    
    # Transfer Tasks from the previous iteration which are still running
    # Only if, this was the last iteration of a step
    if first_step
        for scheduler in task_sim.agent_schedulers
            transfer_wait_queue(scheduler)
        end
    end

    result = TaskIterationResult()
    @sync begin 
        for scheduler in task_sim.agent_schedulers
            # Execute all tasks subsequently until no task can or is allowed to run
            # based on the simulation time
            Threads.@spawn begin
                while true
                    next_task = maybepopfirst!(scheduler.queue)
                    if isnothing(next_task)
                        @debug "Done with the scheduler"
                        break
                    end 
                    
                    # Every time a task is running the state can change, so another iteration has to be calced
                    result.state_changed = true
                    
                    task = something(next_task)
                    if isa(task, Task)
                        @debug "Continue the old Task!" task
                        notify(scheduler.events[task][1])
                    else 
                        @debug "Processing new Task!"
                        func,td,event = task
                        task = do_schedule(func, scheduler, td, event)
                    end

                    @debug "Waiting..."
                    out = wait_for_finish_or_sleeping(scheduler, task, step_size_s)
                    @debug "Finished..."

                    if !isnothing(out.result)
                        notify(scheduler.tasks[task][2])
                        result.task_to_result[uuid4()] = TaskResult(true, task_sim.clock.simulation_time, out)
                        
                        # clean up task data
                        maybepop!(scheduler.tasks, task)
                        if haskey(scheduler.events, task)
                            maybepop!(scheduler.events, task)
                        end
                        
                        @debug "A task has been finished" out.result
                    elseif out.cont
                        push!(scheduler.queue, task)
                        @debug "The task $task needs another iteration!"
                    else
                        push!(scheduler.wait_queue, task)
                        @debug "The task will be proccesed in the next step_iteration"
                    end
                end
            end
        end
    end
    @debug "Done with task iteration"
    return result
end