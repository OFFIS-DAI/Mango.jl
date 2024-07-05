"""
Placeholder for a short summary about mango.
"""
module Mango

export @agent,
    @role,
    @shared,
    Role,
    Agent,
    Container,
    send_message,
    send_tracked_message,
    reply_to,
    register,
    AgentRoleHandler,
    AgentContext,
    RoleContext,
    add,
    subscribe_message,
    subscribe_send,
    emit_event,
    get_model,
    subscribe_event,
    TCPProtocol,
    start,
    shutdown,
    AgentAddress,
    address, 
    aid,
    setup,
    handle_event

include("util/scheduling.jl")
include("util/encode_decode.jl")
using .EncodeDecode

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
