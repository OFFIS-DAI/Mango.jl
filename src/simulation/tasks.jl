export TaskIterationResult, TaskResult, TaskSimulation, create_agent_scheduler, step_iteration, SimulationScheduler, SimpleTaskSimulation

using UUIDs
using Dates
using ConcurrentCollections

"""
Defines the result of a task.
"""
struct TaskResult
    done::Bool
    finish_time::DateTime
    raw_result::Any
end

"""
Define the result of an whole iteration of the task
simulation
"""
@kwdef mutable struct TaskIterationResult
    task_to_result::Dict{UUID,TaskResult} = Dict()
    state_changed::Bool = false
end

"""
Abstract type to define a TaskSimulation
"""
abstract type TaskSimulation end

"""
    create_agent_scheduler(task_sim::TaskSimulation)

Create the scheduler used in the agents by the given `task_sim`.
"""
function create_agent_scheduler(task_sim::TaskSimulation)
    throw(ErrorException("Please implement create_agent_scheduler(...)"))
end

"""
    step_iteration(task_sim::TaskSimulation, step_size_s::Real)::TaskIterationResult

Execute an iteration for a step of the simulation, which time is stepped with the `step_size_s`. 
    
Can be called repeatedly if new tasks are spawn as a result of other tasks or as result of arriving messages. 
"""
function step_iteration(task_sim::TaskSimulation, step_size_s::Real)::TaskIterationResult
    throw(ErrorException("Please implement step_iteration(...)"))
end

"""
    determine_next_event_time(task_sim::TaskSimulation)

Determines the time of the next event, which shall occur.
Used for the discrete event simulation type.
"""
function determine_next_event_time(task_sim::TaskSimulation)
    throw(ErrorException("Please implement determine_next_event_time(...)"))
end

"""
Default implementation of the interface.
"""
@kwdef mutable struct SimpleTaskSimulation <: TaskSimulation
    clock::Clock
    simulation_schedulers::Vector{SimulationScheduler} = Vector{SimulationScheduler}()
end

function add_simulation_scheduler!(task_sim::SimpleTaskSimulation, simulation_scheduler::SimulationScheduler)
    push!(task_sim.simulation_schedulers, simulation_scheduler)
end

function determine_next_event_time(task_sim::SimpleTaskSimulation)
    event_times = [determine_next_event_time_with(scheduler, task_sim.clock.simulation_time) for scheduler in task_sim.simulation_schedulers]
    event_times = event_times[event_times.!=nothing]
    if length(event_times) <= 0
        return nothing
    end
    return findmin(event_times)[1]
end

function create_agent_scheduler(task_sim::SimpleTaskSimulation)
    scheduler = SimulationScheduler(clock=task_sim.clock)
    push!(task_sim.simulation_schedulers, scheduler)
    return scheduler
end

function transfer_wait_queue(scheduler::SimulationScheduler)
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
        for scheduler in task_sim.simulation_schedulers
            transfer_wait_queue(scheduler)
        end
    end

    result = TaskIterationResult()
    @sync begin
        for scheduler in task_sim.simulation_schedulers
            # Execute all tasks subsequently until no task can or is allowed to run
            # based on the simulation time
            Threads.@spawn begin
                while true
                    next_task = maybepopfirst!(scheduler.queue)
                    if isnothing(next_task)
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
                        func, td, event = task
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
