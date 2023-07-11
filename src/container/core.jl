module ContainerCore
export Container, register, send_message, start

using ..ContainerAPI
using ..AsyncUtil
using ..AgentCore: Agent, dispatch_message
using ..ProtocolCore

import ..ContainerAPI.send_message

using Parameters
using Base.Threads

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# prefix for the generated aid's
AGENT_PREFIX::String = "agent"

"""
The default container struct, representing the container as actor. The container is implemented
by composition. This means the container consists of different implementations of base types, which
define the behavior of the container itself. That being said, the same container generally
able to send messages via different protocols using different codecs.
"""
@with_kw mutable struct Container <: ContainerInterface
    agents::Dict{String,Agent} = Dict()
    agent_counter::Integer = 0
    protocol::Union{Nothing,Protocol} = nothing
    codec::Any = (msg, meta) -> msg
end

"""
Starts the container and initialized all its components. After the call the container
start to act as the communication layer.
"""
function start(container::Container)
    init(container.protocol, 
    () -> false, 
    (msg, source) -> forward_message(container, msg, Dict(), "agent1"))
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
function register(container::Container, agent::Agent, suggested_aid::Union{String,Nothing}=nothing)
    actual_aid::String = "$AGENT_PREFIX$(container.agent_counter)"
    if isnothing(suggested_aid) && haskey(container.agents, suggested_aid)
        actual_aid = suggested_aid
    end
    container.agents[actual_aid] = agent
    agent.aid = actual_aid
    container.agent_counter += 1
    return agent.aid
end

"""
Internal function of the container, which forward the message to the correct agent in the container.
At this point it has already been evaluated the message has to be routed to an agent in control of
the container. 
"""
function forward_message(container::Container, msg::Any, meta::Dict, receiver_id::String)
    if isnothing(receiver_id)
        @warn "Got a message missing an agent id!"
    else
        if !haskey(container.agents, receiver_id)
            @warn "Container $(container.agents) has no agent with id: $receiver_id"
        else
            agent = container.agents[receiver_id]
            return Threads.@spawn dispatch_message(agent, msg, meta)
        end
    end
end

"""
Send a message `message` with the metadata `meta` using the given container `container`
to the agent with the receiver id `receiver_id`.

Currently only support internal messaging. It will always be assumed that the receiver_id
exists inside the given `container``.`
"""
function send_message(
    container::Container,
    message::Any,
    meta::Dict,
    receiver::Any
)
    if typeof(receiver) === String
        return forward_message(container, message, meta, receiver)
    end
    return send(container.protocol, receiver, container.codec(message, meta))
end

end
