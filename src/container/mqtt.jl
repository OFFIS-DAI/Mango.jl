export MQTTProtocol,
    send,
    init,
    close,
    id,
    has_message,
    get_messages_channel,
    disconnect,
    subscribe,
    is_connected!

using Mosquitto
using Sockets: InetAddr

# TODO TLS and connection handling for that

mutable struct MQTTProtocol <: Protocol{String}
    client::Client
    broker_addr::InetAddr
    connected::Bool
    msg_channel::Channel
    conn_channel::Channel
    topic_to_aid::Dict{String,Vector{String}}

    function MQTTProtocol(client_id::String, broker_addr::InetAddr)
        # Have to cast types for the MQTT client constructor.
        c = Client(string(broker_addr.host), Int64(broker_addr.port); id=client_id)
        msg_channel = get_messages_channel(c)
        conn_channel = get_connect_channel(c)
        return new(c, broker_addr, false, msg_channel, conn_channel, Dict{String,Vector{String}}())
    end
end

"""
Initialize the Mosquitto looping task. This checks for incoming messages and 
forwards their content to the container.

# Returns

Created Tasks
"""
function init(protocol::MQTTProtocol, stop_check::Function, data_handler::Function)
    tasks = []
    listen_task = errormonitor(
        Threads.@spawn begin
            try
                Mosquitto.loop_start(protocol.client)

                # listen for incoming messages and run callback
                while true
                    temp = take!(protocol.msg_channel)
                    topic = temp.topic
                    message = temp.payload

                    # guaranteed to be a key in the dict unless something went seriously wrong on registration
                    Threads.@spawn data_handler(message, topic; receivers=protocol.topic_to_aid[topic])
                end
            catch err
                if isa(err, InterruptException) || isa(err, Base.IOError)
                    # nothing
                else
                    @error "Caught an unexpected error in listen" exception =
                        (err, catch_backtrace())
                end
            finally
                close(protocol)
            end
        end
    )

    return listen_task, tasks
end

"""
Send a message `message` to topic `destination` on the clients MQTT broker . 

# Returns
Return value and message id from MQTT library.
"""
function send(protocol::MQTTProtocol, destination::String, message::Any)
    publish(protocol.client, destination, message)
end

"""
Returns the namethe client is registered with at its broker.
"""
function id(protocol::MQTTProtocol)
    return protocol.client.id
end

"""
Polls the connection channel and updates the protocols internal connection flag accordingly.

# Returns
The connection status as bool.
"""
function is_connected!(protocol::MQTTProtocol)::Bool
    while !isempty(protocol.conn_channel)
        conncb = take!(protocol.conn_channel)

        if conncb.val == 1
            protocol.connected = true
        elseif conncb.val == 0
            protocol.connected = false
        end
    end

    return protocol.connected
end

"""
Subscribe the MQTT client of the protocol to `topic`.
"""
function subscribe(protocol::MQTTProtocol, topic::String; qos::Int=1)
    Mosquitto.subscribe(protocol.client, topic; qos)
end

"""
Disconnect the client from the broker and stop the message loop.
"""
function close(protocol::MQTTProtocol)
    if is_connected!(protocol)
        disconnect(protocol.client)
        Mosquitto.loop_stop(protocol.client)
    end
end

function parse_id(_::MQTTProtocol, id::Any)::String
    return string(id)
end


"""
Notify the client that a new agent has been registered. Registrations expects a kwarg `topics` 
to subscribe the agent to. 
If any topic is not yet subscribed by the client `subscribe` is called for it.
"""
function notify_register(protocol::MQTTProtocol, aid::String; kwargs...)
    topics = :topics in keys(kwargs) ? kwargs[:topics] : []

    for topic ∈ topics
        if topic ∉ keys(protocol.topic_to_aid)
            protocol.topic_to_aid[topic] = [aid]
            subscribe(protocol, topic)
            continue
        end

        if aid ∉ protocol.topic_to_aid[topic]
            push!(protocol.topic_to_aid[topic], aid)
        end
    end
end