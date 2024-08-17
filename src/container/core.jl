export Container, register, send_message, start, shutdown, notify_ready

using Parameters
using OrderedCollections
using Base.Threads

# id key for the receiver
RECEIVER_ID::String = "receiver_id"
# prefix for the generated aid's
AGENT_PREFIX::String = "agent"

# id key for mqtt broker
BROKER::String = "broker"
# id key for mqtt topic
TOPIC::String = "topic"

"""
The default container struct, representing the container as actor. The container is implemented
by composition. This means the container consists of different implementations of base types, which
define the behavior of the container itself. That being said, the same container generally
able to send messages via different protocols using different codecs.
"""
@kwdef mutable struct Container <: ContainerInterface
    agents::Dict{String,Agent} = Dict()
    agent_counter::Integer = 0
    protocol::Union{Nothing,Protocol} = nothing
    codec::Any = (encode, decode)
    shutdown::Bool = false
    loop::Any = nothing
    tasks::Any = nothing
end

function agents(container::Container)
    return values(container.agents)
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
function process_message(container::Container, msg_data::Any, sender_addr::Any; receivers=nothing)
    msg = container.codec[2](msg_data)
    content, meta = msg["content"], msg["meta"]
    if haskey(meta, SENDER_ADDR)
        meta[SENDER_ADDR] = parse_id(container.protocol, meta[SENDER_ADDR])
    else
        meta[SENDER_ADDR] = nothing
    end
    forward_message(container, content, meta; receivers=receivers)
end

"""
Get protocol addr part
"""
function protocol_addr(container::Container)
    if isnothing(container.protocol)
        return nothing
    end
    return id(container.protocol)
end

"""
Starts the container and initialized all its components. After the call the container
start to act as the communication layer.
"""
function start(container::Container)
    if !isnothing(container.protocol)
        container.loop, container.tasks = init(
            container.protocol,
            () -> container.shutdown,
            (msg_data, sender_addr; receivers=nothing) -> process_message(container, msg_data, sender_addr; receivers=receivers),
        )
    end
    for agent in values(container.agents)
        notify_start(agent)
    end
end

"""
Mark the agent system as ready, needs to be detected and called manually!
"""
function notify_ready(container::Container)
    for agent in values(container.agents)
        notify_ready(agent)
    end
end

"""
Shut down the container. It is always necessary to call it for freeing bound resources
"""
function shutdown(container::Container)
    container.shutdown = true
    if !isnothing(container.protocol)
        close(container.protocol)
    end
    if !isnothing(container.tasks)
        for task in container.tasks
            wait(task)
        end
    end

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
    container::Container,
    agent::Agent,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
)
    actual_aid::String = "$AGENT_PREFIX$(container.agent_counter)"
    if !isnothing(suggested_aid) && !haskey(container.agents, suggested_aid)
        actual_aid = suggested_aid
    end
    container.agents[actual_aid] = agent
    agent.aid = actual_aid
    agent.context = AgentContext(container)
    container.agent_counter += 1

    if !isnothing(container.protocol)
        notify_register(container.protocol, actual_aid; kwargs...)
    end
    return agent
end

"""
Internal function of the container, which forward the message to the correct agent in the container.
At this point it has already been evaluated the message has to be routed to an agent in control of
the container. 
"""
function forward_message(container::Container, msg::Any, meta::AbstractDict; receivers=nothing)
    # if not multicast: single cast
    if isnothing(receivers)
        receivers = RECEIVER_ID in keys(meta) ? [meta[RECEIVER_ID]] : nothing
    end

    send_tasks = []

    if isnothing(receivers)
        @warn "Got a message missing an agent id!"
    else
        for receiver in receivers
            if !haskey(container.agents, receiver)
                @warn "Container $(container.agents) has no agent with id: $receiver"
            else
                agent = container.agents[receiver]
                @debug "Dispatch a message to agent $(aid(agent))" typeof(msg) get(meta, SENDER_ID, "") protocol_addr(container)
                push!(send_tasks, @spawnlog dispatch_message(agent, msg, meta))
            end
        end
    end

    # return the single wait task syncing all sends 
    # so we can wait for the full message action to be done outside
    if isempty(send_tasks)
        # return an empty finished task so this function
        # can always be waited on
        return @async begin end
    end

    return @sync(send_tasks)[1]
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
    agent_adress::AgentAddress,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)
    receiver_id = agent_adress.aid
    receiver_addr = agent_adress.address
    tracking_id = agent_adress.tracking_id

    meta = OrderedDict{String,Any}()
    for (key, value) in kwargs
        meta[string(key)] = value
    end
    meta[RECEIVER_ID] = receiver_id
    meta[SENDER_ID] = sender_id
    meta[TRACKING_ID] = tracking_id

    if !isnothing(container.protocol)
        meta[SENDER_ADDR] = id(container.protocol)
    else
        meta[SENDER_ADDR] = nothing
    end

    if isnothing(receiver_addr) || receiver_addr == id(container.protocol)
        return forward_message(container, content, meta)
    end

    @debug "Send a message to ($receiver_id, $receiver_addr), from $sender_id" typeof(content)

    return @spawnlog send(
        container.protocol,
        receiver_addr,
        container.codec[1](to_external_message(content, meta)),
    )
end


"""
Send message version for MQTT topics. 
Note that there is no local message forwarding here because messages always get
pushed to a broker and are not directly addressed to an agennt.
"""
function send_message(
    container::Container,
    content::Any,
    mqtt_address::MQTTAddress,
    kwargs...,
)
    broker = mqtt_address.broker
    topic = mqtt_address.topic

    meta = OrderedDict{String,Any}()
    for (key, value) in kwargs
        meta[string(key)] = value
    end
    meta[BROKER] = broker
    meta[TOPIC] = topic

    if !isnothing(container.protocol)
        meta[SENDER_ADDR] = id(container.protocol)
    end

    return @spawnlog send(
        container.protocol,
        topic,
        container.codec[1](to_external_message(content, meta)),
    )
end

