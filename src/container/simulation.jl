module SimulationContainerCore
export SimulationContainer, register, send_message, shutdown, protocol_addr


using ..ContainerAPI
using ..AgentCore: Agent, AgentContext, dispatch_message, stop_and_wait_for_all_tasks

import ..ContainerAPI.send_message, ..ContainerAPI.protocol_addr
import ..AgentCore: shutdown

using Parameters
using OrderedCollections
using Base.Threads
using Dates
using ConcurrentCollections

using ..TaskSimulationModule
using ..CommunicationSimulationModule

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# prefix for the generated aid's
AGENT_PREFIX::String = "agent"

function create_simulation_container(start_time::DateTime, communication_sim::Union{Nothing,CommunicationSim}=nothing, task_sim::Union{Nothing,TaskSimulation}=nothing) 
    container = SimulationContainer()
    container.clock = Clock(start_time)
    if !isnothing(communication_sim)
        container.communication_sim = communication_sim
    end
    if !isnothing(task_sim)
        container.task_sim = task_sim
    end
    return container
end

@with_kw mutable struct SimulationContainer <: ContainerInterface
    agents::Dict{String,Agent} = Dict()
    communication_sim::CommunicationSim = SimpleCommunicationSimulation()
    task_sim::TaskSimulation = SimpleTaskSimulation()
    agent_counter::Integer = 0
    shutdown::Bool = false
    clock::Clock = Clock(DateTime(0))
    message_queue::ConcurrentQueue{Tuple{Any,AbstractDict}} = ConcurrentQueue{Tuple{Any,AbstractDict}}()
end

@with_kw struct CommunicationSimulationResult
    results::Vector{CommunicationIterationResult} = Vector()
end
@with_kw struct TaskSimulationResult
    results::Vector{TaskIterationResult} = Vector()
end

struct SimulationResult
    time_elapsed::Float64
    communication_result::CommunicationSimulationResult
    task_result::TaskSimulationResult
end

function to_message_package(message_tuple::Tuple{Any, AbstractDict}, simulation_time::DateTime)::MessagePackage
    sender_aid = message_tuple[2][SENDER_ID]
    receiver_aid = message_tuple[2][RECEIVER_ID]
    return MessagePackage(sender_aid, receiver_aid, simulation_time, message_tuple)
end

function to_cs_input(message_queue::ConcurrentQueue{Tuple{Any,AbstractDict}}, simulation_time::DateTime)::Vector{MessagePackage}
    messages_packages = Vector()
    while !empty(message_queue)
        message = pop!(message_queue)
        push(messages_packages, to_message_package(message, simulation_time))
    end
    return messages_packages
end

function cs_step_iteration(container::SimulationContainer, step_size_s::Float64)::CommunicationSimulationResult
    message_packages = to_cs_input(container.message_queue, container.clock.simulation_time)
    comm_result::CommunicationIterationResult = calculate_communication(container.communication_sim, 
                            container.clock, 
                            message_packages)
    for (mp, pr) in sort(zip(message_packages, comm_result.package_results), by=t->t[2].delay)
        if step_size_s >= pr.delay && pr.reached
            process_message(container, mp.content[1], mp.content[2])
        else
            # process it later
            push!(container.message_queue, mp.content)
        end
    end
end

function step(container::SimulationContainer, step_size_s::Float64=900.0)::SimulationResult
    empty = false
    
    task_sim_result = TaskSimulationResult()
    comm_sim_result = CommunicationSimulationResult()
    elapsed = @elapsed begin 
        while !empty
            task_iter_result = nothing
            comm_iter_result = nothing
            @sync begin 
                Threads.@spawn task_iter_result = step_iteration(container.task_sim)
                Threads.@spawn comm_iter_result = cs_step_iteration(container, step_size_s)
            end
            push!(task_sim_result.results, task_iter_result)
            push!(comm_sim_result.results, comm_iter_result)
            empty = comm_iter_result.state_changed || task_iter_result.state_changed
        end
    end
    
    container.clock += Second(step_size_s)

    return SimulationResult(elapsed, comm_sim_result, task_sim_result)
end

"""
Get protocol addr part
"""
function protocol_addr(container::SimulationContainer)
    return nothing
end

"""
Shut down the container. It is always necessary to call it for freeing bound resources
"""
function shutdown(container::Container)
    container.shutdown = true
    
    for agent in values(container.agents)
        shutdown(agent)
    end
end

"""
Register an agent given the target container `container`. While registering
an aid will be generated and assigned to the agent.

This function will add the agent to the internal list of the container and will from
then on be controlled by the container regarding the messaging activities. That means
the container acts as the gateway of the agent defining its possible way to retrieve 
messages.

# Args
suggested_aid: you can provide an aid yourself. The container will always use that aid
    if possible

# Returns
The actually used aid will be returned.
"""
function register(
    container::SimulationContainer,
    agent::Agent,
    suggested_aid::Union{String,Nothing}=nothing,
)
    actual_aid::String = "$AGENT_PREFIX$(container.agent_counter)"
    if isnothing(suggested_aid) && haskey(container.agents, suggested_aid)
        actual_aid = suggested_aid
    end
    container.agents[actual_aid] = agent
    agent.aid = actual_aid
    agent.context = AgentContext(container)
    container.agent_counter += 1
    
    if !isnothing(container.task_sim)
        agent.scheduler = create_agent_scheduler(container.task_sim)
    end
    
    return agent.aid
end

function process_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
    receiver_id = meta[RECEIVER_ID]

    if !haskey(container.agents, meta[RECEIVER_ID])
        @warn "Container $(container.agents) has no agent with id: $receiver_id"
    else
        agent = container.agents[receiver_id]
        return Threads.@spawn dispatch_message(agent, msg, meta)
    end
end


"""
Internal function of the container, which forward the message to the correct agent in the container.
At this point it has already been evaluated the message has to be routed to an agent in control of
the container. 
"""
function forward_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
    push!(container.message_queue, (msg, meta))
end

"""
Send a message `message` with using the given container `container`
to the agent with the receiver id `receiver_id`. The receivers address 
is used by the chosen protocol to appropriatley route the message to
external participants. To specifiy further meta data of the message
`kwargs` should be used.

# Returns
True if the message has been sent successfully, false otherwise.
"""
function send_message(
    container::SimulationContainer,
    content::Any,
    agent_adress::AgentAddress,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)
    receiver_id = agent_adress.aid
    tracking_id = agent_adress.tracking_id

    meta = OrderedDict{String,Any}()
    for (key, value) in kwargs
        meta[string(key)] = value
    end

    meta[RECEIVER_ID] = receiver_id
    meta[SENDER_ID] = sender_id
    meta[TRACKING_ID] = tracking_id
    meta[SENDER_ADDR] = nothing

    return forward_message(container, content, meta)
end

end
