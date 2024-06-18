module AgentAPI
export Agent, AgentInterface, subscribe_message_handle, subscribe_send_handle, subscribe_event_handle, emit_event_handle, get_model_handle, send_message, send_tracked_message, reply_to, address, aid

import ..ContainerAPI.send_message
using ..ContainerAPI

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

"""
Used internally by the RoleContext to subscribe message handler to the agent.
"""
function subscribe_message_handle(agent::AgentInterface, role::Any, condition::Any, handler::Any) end

"""
Used internally by the RoleContext to subscribe send handler to the agent.
"""
function subscribe_send_handle(agent::AgentInterface, role::Any, handler::Any) end

"""
Used internally by the RoleContext to subscribe to role agent events.
"""
function subscribe_event_handle(agent::AgentInterface, role::Any, event_type::Any, event_handler::Any; condition::Function=(a, b)->true) end

"""
Used internally by the RoleContext to subscribe to role agent events.
"""
function emit_event_handle(agent::AgentInterface, role::Any, event::Any; event_type::Any=nothing) end

"""
Used internally by the RoleContext to subscribe to role agent events.
"""
function get_model_handle(agent::AgentInterface, type::DataType) end

"""
Used internally by the role to get the AgentAddress
"""
function address(agent::AgentInterface) end

"""
Used internally by the role to get the AID
"""
function aid(agent::AgentInterface) end

"""
API Definition for the role context
"""
function send_message(
    agent::AgentInterface,
    content::Any,
    agent_address::AgentAddress;
    kwargs...
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

function send_tracked_message(
    agent::AgentInterface,
    content::Any,
    agent_address::AgentAddress;
    response_handler::Function=(agent,message,meta)->nothing,
    calling_object::Any=nothing,
    kwargs...
)
    @warn "The API send_tracked_message definition has been called, this should never happen. There is most likely an import error."
end

"""
API Definition for directly replying to a message
"""
function reply_to(
    agent::AgentInterface,
    content::Any,
    received_meta::AbstractDict
)
    @warn "The API reply_to definition has been called, this should never happen. There is most likely an import error."
end

end