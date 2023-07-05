module ContainerAPI
export ContainerInterface, send_message

"""
Supertype of every container implementation. This acts as an interface to be used by the agents
in their contexts.
"""
abstract type ContainerInterface end

"""
Send a message `message` with the metadata `meta` using the given container `container`
to the agent with the receiver id `receiver_id`.

This only defines the function API, the actual implementation is done in the core container
module.
"""
function send_message(
    container::ContainerInterface,
    message::Any,
    meta::Dict,
    receiver_id::String
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

end