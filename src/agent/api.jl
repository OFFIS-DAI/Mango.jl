export Agent, send_message, send_tracked_message, reply_to, address, aid, send_and_handle_answer


"""
Supertype of all address types
"""
abstract type Address end

"""
Supertype of the Agent Base type representing an interface, on which methods
can be defined, which should be accessable from the outside, especially from
the roles contained in the specific agent.
"""
abstract type AgentInterface end

"""
Base-type for all agents in mango. Generally exists for type-safety and default
implementations across all agents.
"""
abstract type Agent <: AgentInterface end

function subscribe_message_handle(agent::AgentInterface, role::Any, condition::Any, handler::Any) end

"""
    subscribe_send_handle(agent::AgentInterface, role::Any, handler::Any)

Used internally by the RoleContext to subscribe send handler to the agent.
"""
function subscribe_send_handle(agent::AgentInterface, role::Any, handler::Any) end

"""
    subscribe_event_handle(agent::AgentInterface, role::Any, event_type::Any, event_handler::Any; condition::Function=(a, b) -> true)

Used internally by the RoleContext to subscribe to role agent events.
"""
function subscribe_event_handle(agent::AgentInterface, role::Any, event_type::Any, event_handler::Any; condition::Function=(a, b) -> true) end

"""
    emit_event_handle(agent::AgentInterface, role::Any, event::Any; event_type::Any=nothing)

Used internally by the RoleContext to subscribe to role agent events.
"""
function emit_event_handle(agent::AgentInterface, role::Any, event::Any; event_type::Any=nothing) end

"""
    get_model_handle(agent::AgentInterface, type::DataType)

Used internally by the RoleContext to subscribe to role agent events.
"""
function get_model_handle(agent::AgentInterface, type::DataType) end

"""
    address(agent)

Return the agent address of the agent as [`AgentAddress`](@ref) or [`MQTTAddress`](@ref) depending on the protocol.
"""
function address(agent::AgentInterface) end

"""
    aid(agent)

Return the aid of the agent.
"""
function aid(agent::AgentInterface) end

"""
    send_message(agent, content::Any, agent_address::Address; kwargs...,)

Send a message with the content `content` to the agent represented by `agent_address`. 

This method will always set a sender_id. Additionally, further keyword arguments can be defined to fill the 
internal meta data of the message.
"""
function send_message(
    agent::AgentInterface,
    content::Any,
    agent_address::Address;
    kwargs...,
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end


"""
    send_tracked_message(agent, content, agent_address; 
        response_handler::Function(agent, message, meta)::nothing,
        calling_object::Any=nothing,
        kwargs...,
    )

Send a message with the content `content` to the agent represented by `agent_address`. This function will set
a generated tracking_id to the address, which allows the identification of the dialog. 

It is possible to define a `response_handler`, to which a function can be assigned, which handles the answer 
to this message call. Note that the resonding agent needs to use the same tracking id in the response, ideally
[`reply_to`](@ref) is used to achieve this automatically. 

This method will always set a sender_id. Additionally, further keyword arguments can be defines to fill the 
internal meta data of the message.
"""
function send_tracked_message(
    agent::AgentInterface,
    content::Any,
    agent_address::Address;
    response_handler::Function=(agent, message, meta) -> nothing,
    calling_object::Any=nothing,
    kwargs...,
)
    @warn "The API send_tracked_message definition has been called, this should never happen. There is most likely an import error."
end

"""
    send_and_handle_answer(
        response_handler::Function(agent, message, meta)::nothing,
        agent::AgentInterface,
        content::Any,
        agent_address::Address;
        calling_object::Any=nothing,
        kwargs...)

Convenience method for sending tracked messages with response handler to the answer.

Sends a tracked message with a required response_handler to enable to use the syntax
```
send_and_handle_answer(...) do agent, message, meta
	# handle the answer
end
```
"""
function send_and_handle_answer(
    response_handler::Function,
    agent::AgentInterface,
    content::Any,
    agent_address::Address;
    calling_object::Any=nothing,
    kwargs...)
    @warn "The API send_and_handle_answer definition has been called, this should never happen. There is most likely an import error."
end

"""
    reply_to(agent, content, received_meta)

Convenience method to reply to a received message using the meta the agent received. This reduces the regular send_message as response
`send_message(agent, "Pong", AgentAddress(aid=meta["sender_id"], address=meta["sender_addr"]))`
to
`reply_to(agent, "Pong", meta)`

Furthermore it guarantees that agent address (including the tracking id, which is part of the address!) is correctly passed to the mango
container.
"""
function reply_to(
    agent::AgentInterface,
    content::Any,
    received_meta::AbstractDict,
)
    @warn "The API reply_to definition has been called, this should never happen. There is most likely an import error."
end

"""
    forward_to(agent, content, forward_to_address, received_meta; kwargs...)

Forward the message to a specific agent using the metadata received on handling
the message. This method essentially simply calls send_message on the input given, but
also adds and fills the correct metadata fields to mark the message as forwarded. 

For this the following meta data is set.
'forwarded=`true`',
'forwarded_from_address=`address of the original sender`',
'forwarded_from_id=`id of the original sender`'
"""
function forward_to(agent::AgentInterface,
    content::Any,
    forward_to_address::Address,
    received_meta::AbstractDict;
    kwargs...)
    @warn "The API forward_to definition has been called, this should never happen. There is most likely an import error."
end