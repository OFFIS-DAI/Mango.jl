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

using ..TaskSimulation
using ..CommunicationSimulation

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# prefix for the generated aid's
AGENT_PREFIX::String = "agent"

function create_simulation_container(start_time::DateTime, communication_sim::Union{Nothing,CommunicationSim}=nothing) 
    container = SimulationContainer()
    container.clock = Clock(start_time)
    if !isnothing(communication_sim)
        container.communication_sim = communication_sim
    end
    return container
end

@with_kw mutable struct SimulationContainer <: ContainerInterface
    agents::Dict{String,Agent} = Dict()
    communication_sim::CommunicationSim = SimpleCommunicationSim()
    task_sim::TaskSim = TaskSim()
    agent_counter::Integer = 0
    shutdown::Bool = false
    clock::Clock = Clock(DateTime(0))
end

struct SimulationResult
    time_elapsed::Float64
    communication_result::CommunicationResult
    task_result::TaskResult
end

function step(container::SimulationContainer, step_size_s::Float64=900.0)::SimulationResult
    container.clock += Second(step_size_s)
    continue_tasks(container.clock, container.clock.simulation_time)
    
    empty = false
    while !empty
        empty = step(container.task_sim).state_changed
        empty = empty || step(container.communication_sim).state_changed

        @sync begin 
            wait(container.task_sim)
            wait(container.communication_sim)
        end
    end
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

"""
Internal function of the container, which forward the message to the correct agent in the container.
At this point it has already been evaluated the message has to be routed to an agent in control of
the container. 
"""
function forward_message(container::Container, msg::Any, meta::AbstractDict)
    receiver_id = meta[RECEIVER_ID]

    if isnothing(receiver_id)
        @warn "Got a message missing an agent id!"
    else
        if !haskey(container.agents, meta[RECEIVER_ID])
            @warn "Container $(container.agents) has no agent with id: $receiver_id"
        else
            agent = container.agents[receiver_id]
            return Threads.@spawn dispatch_message(agent, msg, meta)
        end
    end
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
    container::Container,
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
