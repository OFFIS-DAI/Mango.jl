export TaskIterationResult, TaskResult, TaskSimulation, create_agent_scheduler, step_iteration, SimulationScheduler, SimpleTaskSimulation

using UUIDs
using Dates
using ConcurrentCollections

# Interface Definition
struct TaskResult
    done::Bool
    finish_time::DateTime
    raw_result::Any
end

@kwdef struct TaskIterationResult 
    task_to_result::Dict{UUID, TaskResult} = Dict()
    state_changed::Bool = false
end

abstract type TaskSimulation end

function create_agent_scheduler(task_sim::TaskSimulation)
    throw(ErrorException("Please implement create_agent_scheduler(...)"))
end
function step_iteration(task_sim::TaskSimulation, clock::Clock)::TaskIterationResult 
    throw(ErrorException("Please implement step_iteration(...)"))
end

# Scheduler Definition
@kwdef struct SimulationScheduler <: AbstractScheduler
    tasks::AbstractDict{Task,TaskData} = ConcurrentDict{Task,TaskData}()
    queue::ConcurrentQueue{Tuple{Function,TaskData,Condition}} = ConcurrentQueue{Tuple{Function,TaskData,Condition}}()
end

function tasks(scheduler::SimulationScheduler)
    return scheduler.tasks
end

function schedule(f::Function, scheduler::SimulationScheduler, data::TaskData)
    condition = Condition()
    push!(scheduler.queue, (f, data, condition))
    return condition
end

# Default Implementation of Interface
@kwdef struct SimpleTaskSimulation <: TaskSimulation
    agent_schedulers::Vector{SimulationScheduler} = Vector{SimulationScheduler}()
end

function create_agent_scheduler(task_sim::SimpleTaskSimulation)
    scheduler = SimulationScheduler()
    push!(task_sim.agent_schedulers, scheduler)
    return scheduler
end

function step_iteration(task_sim::SimpleTaskSimulation, clock::Clock)::TaskIterationResult 
    result = TaskIterationResult()
    for scheduler in task_sim.agent_schedulers
        while true
            next_task = maybepopfirst!(scheduler.queue)
            if isnothing(next_task)
                break
            end 
            before = length(scheduler.queue)
            
            out = wait(schedule(next_task[1], scheduler, next_task[2]))
            notify(next_task[3])

            result.state_changed = before > length(scheduler.queue)
            result.task_to_result[uuid4()] = TaskResult(true, clock.simulation_time, out)
        end
    end
    return result
end