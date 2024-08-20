
export ContainerInterface, send_message, register, start, shutdown, protocol_addr, agents, Address, AgentAddress, MQTTAddress, SENDER_ADDR, SENDER_ID, TRACKING_ID

"""
Key for the sender address in the meta dict
"""
SENDER_ADDR::String = "sender_addr"
"""
Key for the sender in the meta dict
"""
SENDER_ID::String = "sender_id"
""" 
Key for the tracking number used for dialogs in the meta dict
"""
TRACKING_ID::String = "tracking_id"

"""
Supertype of every container implementation. This acts as an interface to be used by the agents
in their contexts.
"""
abstract type ContainerInterface end

"""
Default AgentAddress base type, where the agent identifier is based on the container created agent id (aid).
Used with the TCP protocol.
"""
@kwdef struct AgentAddress <: Address
    aid::Union{String,Nothing}
    address::Any = nothing
    tracking_id::Union{String,Nothing} = nothing
end

"""
Connection information for an MQTT topic on a given broker. 
Used with the MQTT protocol. 
"""
@kwdef struct MQTTAddress <: Address
    broker::Any = nothing
    topic::String
end

"""
    send_message(
    container::ContainerInterface,
    content::Any,
    address::Address,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)

Send a message `message` using the given container `container`
to the given address. Additionally, further keyword
arguments can be defines to fill the internal meta data of the message.
"""
function send_message(
    container::ContainerInterface,
    content::Any,
    address::Address,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

"""
    protocol_addr(container)

Return technical address of the container.
"""
function protocol_addr(container::ContainerInterface) end

"""
    start(container)

Start the container. It is recommended to use [`activate`](@ref) instead of starting manually.

What exactly happend highly depends on the protocol and the container implmentation.
For example, for TCP the container binds on IP and port, and the listening loop started.
"""
function start(container::ContainerInterface) end

"""
    shutdown(container)

Shutdown the container. Here all loops are closed, resources freed. It is recommended to use [`activate`](@ref) 
instead of shutting down manually.
"""
function shutdown(container::ContainerInterface) end

"""
    register(
    container,
    agent,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
)

Register the agent to the container. Retun the agent itself for convenience.

Normally the aid is generated, however it is possible to suggest an aid, which will be used
if it has not been used yet and if it is not conflicting with the default naming pattern (agent0, agent1, ...)
"""
function register(
    container::ContainerInterface,
    agent::AgentInterface,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
) end

"""
    agents(container)

Return the agents of the container. The agents have a fixed order.
"""
function agents(container::ContainerInterface) end
