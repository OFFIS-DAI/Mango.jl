"""
Placeholder for a short summary about mango.
"""
module Mango

export @agent, @role, Role, Agent, Container, send_message, register, @asynclog, AgentRoleHandler, AgentContext, RoleContext, add, subscribe, TCPProtocol, start, shutdown


include("util/async.jl")
using .AsyncUtil

include("container/api.jl")
using .ContainerAPI

include("agent/api.jl")
using .AgentAPI

include("agent/role.jl")
using .AgentRole

include("agent/core.jl")
using .AgentCore

include("container/protocol.jl")
using .ProtocolCore

include("container/core.jl")
using .ContainerCore


end # module
