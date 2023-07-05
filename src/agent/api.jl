module AgentAPI
export Agent, AgentInterface, subscribe_handle

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
function subscribe_handle(agent::Agent, role::Any, condition::Any, handler::Any) end

end