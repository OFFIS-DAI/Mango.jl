module TaskSimulation


# Task Sim
@with_kw struct SimulationScheduler <: AbstractScheduler
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

@with_kw struct TaskSim 
    agent_schedulers::Vector{SimulationScheduler} = Vector{SimulationScheduler}()
end

function create_agent_scheduler(task_sim::TaskSim)
    scheduler = SimulationScheduler()
    push!(task_sim.agent_schedulers, scheduler)
    return scheduler
end

struct TaskResult
    done::Bool
    finish_time::DateTime
end

@with_kw struct TaskSimResult 
    task_to_result::Dict{UUID, TaskResult} = Dict()
    state_changed::Bool = false
end

function step(task_sim::TaskSim)::TaskSimResult 
    result = TaskSimResult()
    for scheduler in task_sim.agent_schedulers
        while !empty(scheduler.queue)
            
        end
    end
end
end