module ContainerAPI
export ContainerInterface, send_message

"""
Supertype of every container implementation. This acts as an interface to be used by the agents
in their contexts.
"""
abstract type ContainerInterface end

"""
Default AgentAdress base type, where the agent identifier is based on the container created agent id (aid).
"""
struct AgentAdress{T}
    aid::String
    address::T
end

"""
Send a message `message using the given container `container`
to the agent with the receiver id `receiver_id` at the address `receiver_addr`. If you want
to be able to receive an answer, a sender_id can be defined. Additionally, further keyword
arguments can be defines to fill the internal meta data of the message.

This only defines the function API, the actual implementation is done in the core container
module.
"""
function send_message(
    container::ContainerInterface,
    content::Any,
    agent_adress::AgentAdress{T},
    sender_id::Union{Nothing,String}=nothing;
    kwargs...
) where {T}
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end


end