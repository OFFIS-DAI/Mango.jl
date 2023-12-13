module ContainerCore
export Container, register, send_message, start, shutdown

import ..Mango: @asynclog
using ..ContainerAPI
using ..AgentCore: Agent, AgentContext, dispatch_message
using ..ProtocolCore
using ..EncodeDecode

import ..ContainerAPI.send_message

using Parameters
using OrderedCollections
using Base.Threads

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# id key for the sender address
SENDER_ADDR::String = "sender_addr"
# id key for the sender 
SENDER_ID::String = "sender_id"
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
    codec::Any = (EncodeDecode.encode, EncodeDecode.decode)
    shutdown::Bool = false
    loop::Any = nothing
    tasks::Any = nothing
end

"""
Internal representation of a message in mango
"""
struct MangoMessage
    content::Any
    meta::Dict{String,Any}
end

"""
Process the message data after rawly receiving them.
"""
function process_message(container::Container, msg_data::Any, sender_addr::Any)
    msg = container.codec[2](msg_data)
    content, meta = msg["content"], msg["meta"]
    if haskey(meta, SENDER_ADDR)
        meta[SENDER_ADDR] = parse_id(container.protocol, meta[SENDER_ADDR])
    end
    forward_message(container, content, meta)
end

"""
Starts the container and initialized all its components. After the call the container
start to act as the communication layer.
"""
function start(container::Container)
    container.loop, container.tasks = init(
        container.protocol,
        () -> container.shutdown,
        (msg_data, sender_addr) -> process_message(container, msg_data, sender_addr),
    )
end

"""
Shut down the container. It is always necessary to call it for freeing bound resources
"""
function shutdown(container::Container)
    container.shutdown = true
    close(container.protocol)
    @asynclog Base.throwto(container.loop, InterruptException())

    for task in container.tasks
        wait(task)
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
    container::Container,
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

function to_external_message(content::Any, meta::AbstractDict)
    return MangoMessage(content, meta)
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
    receiver_id::String,
    receiver_addr::Any=nothing,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)

    meta = OrderedDict{String,Any}()
    for (key, value) in kwargs
        meta[string(key)] = value
    end
    meta[RECEIVER_ID] = receiver_id
    meta[SENDER_ID] = sender_id

    if !isnothing(container.protocol)
        meta[SENDER_ADDR] = id(container.protocol)
    end

    if isnothing(receiver_addr) || receiver_addr == id(container.protocol)
        return forward_message(container, content, meta)
    end

    return @asynclog send(
        container.protocol,
        receiver_addr,
        container.codec[1](to_external_message(content, meta)),
    )
end

end
