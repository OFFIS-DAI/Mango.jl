
export Protocol, send, start, close, id, notify_register, init

"""
Type for all implementations of protocols, acts like an interface. A protocol defines the way message are processed and especially sent and received 
to an other peer. F.E. A protocol could be to send messages using a plain TCP connection, which would indicate that an internet address (host + port)
is required for the communication.

The parameterized type T indicates type, which defines the address data of the receiver and sender.

Every protocol has to define two methods.
1. send: defines the behavior of the protocol when an agents sends a messages
2. init: defines the necessary steps to initialize (especially) the receiver loop and
		 therefore accepts a stop check and a data handler function to indicate when the receiver should stop, 
		 respectively how to dispatch the received message to the correct agent
"""
abstract type Protocol{T} end

"""
Send the message `message` to the agent known by the adress `destination`. How the message is exactly handled is 
determined by the protocol invoked. 

The type of the destination has to match with the protocol. 

# Returns
The function returns a boolean indicating whether the message was successfull sent
"""
function send(protocol::Protocol{T}, destination::T, message::Any) where {T} end

"""
Initialized the protocols internal loops (if exists). In most implementation this would mean that the receiver loop is started.
To handle received messages the `data_handler` function can be passed `(msg, sender) -> your handling code`. 

To control the lifetime of the loops a stop_check should be passed (() -> boolean). If the stop check is true the loops will 
terminate. The exact behavior depends on the implementation though.
"""
function init(protocol::Protocol{T}, stop_check::Function, data_handler::Function) where {T} end

"""
Return the external identifier associated with the protocol (e.g. it could be the host+port, dns name, ...)
"""
function id(protocol::Protocol{T}) where {T} end

"""
Parse different types to the correct type (if required). Should be implemented if the id type is not trivial.
"""
function parse_id(protocol::Protocol{T}, id_data::Any)::T where {T} end

"""
Protocol specific updates called when a new agent is registered.
"""
function notify_register(protocol::Protocol{T}, aid::String; kwargs...) where {T} end

