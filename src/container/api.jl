
export ContainerInterface, send_message, protocol_addr, Address, AgentAddress, MQTTAddress, SENDER_ADDR, SENDER_ID, TRACKING_ID

# id key for the sender address
SENDER_ADDR::String = "sender_addr"
# id key for the sender 
SENDER_ID::String = "sender_id"
# id key for the tracking number used for dialogs
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
	aid::Union{String, Nothing}
	address::Any = nothing
	tracking_id::Union{String, Nothing} = nothing
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
Send a message `message using the given container `container`
to the given address. Additionally, further keyword
arguments can be defines to fill the internal meta data of the message.

This only defines the function API, the actual implementation is done in the core container
module.
"""
function send_message(
	container::ContainerInterface,
	content::Any,
	address::Address,
	sender_id::Union{Nothing, String} = nothing;
	kwargs...,
)
	@warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

"""
Used by the agent to get the protocol addr part
"""
function protocol_addr(container::ContainerInterface) end

function start(container::ContainerInterface) end
function shutdown(container::ContainerInterface) end

function register(
	container::ContainerInterface,
	agent::AgentInterface,
	suggested_aid::Union{String, Nothing} = nothing;
	kwargs...,
) end
