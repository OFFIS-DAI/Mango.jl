module AgentAPI
export Agent, AgentInterface, subscribe_handle, send_message

import ..ContainerAPI.send_message

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
function subscribe_handle(agent::AgentInterface, role::Any, condition::Any, handler::Any) end

"""
API Definition for the role context
"""
function send_message(
    agent::AgentInterface,
    content::Any,
    receiver_id::String,
    receiver_addr::Any=nothing;
    kwargs...
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

end