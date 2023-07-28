module ContainerAPI
export ContainerInterface, send_message

"""
Supertype of every container implementation. This acts as an interface to be used by the agents
in their contexts.
"""
abstract type ContainerInterface end

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
    receiver_id::String,
    receiver_addr::Any=nothing,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

end