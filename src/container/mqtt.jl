export MQTTProtocol,
    get_messages_channel,
    disconnect,
    subscribe

using Mosquitto
using Sockets: InetAddr



mutable struct MQTTProtocol <: Protocol{String}
    client::Client
    broker_addr::InetAddr
    connected::Bool
    active::Bool
    msg_channel::Channel
    conn_channel::Channel
    topic_to_aid::Dict{String,Vector{String}}

    function MQTTProtocol(client_id::String, broker_addr::InetAddr)
        # Have to cast types for the MQTT client constructor.
        c = Client(string(broker_addr.host), Int64(broker_addr.port); id=client_id)
        msg_channel = get_messages_channel(c)
        conn_channel = get_connect_channel(c)
        return new(c, broker_addr, false, false, msg_channel, conn_channel, Dict{String,Vector{String}}())
    end
end

"""
    init(protocol::MQTTProtocol, stop_check::Function, data_handler::Function)

Initialize the Mosquitto looping task for the provided `protocol` and forward incoming messages to `data_handler`. 
"""
function init(protocol::MQTTProtocol, stop_check::Function, data_handler::Function)
    tasks = []
    listen_task = errormonitor(
        Threads.@spawn begin
            try
                run_mosquitto_loop(protocol, data_handler)
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
    run_mosquitto_loop(protocol::MQTTProtocol, data_handler::Function)

Endlessly loops over incoming messages on the `msg_channel` and `conn_channel`` and process their contents. 

Loop is stopped by setting the `protocol.active` flag to false.
"""
function run_mosquitto_loop(protocol::MQTTProtocol, data_handler::Function)
    Mosquitto.loop_start(protocol.client)
    protocol.active = true

    # listen for incoming messages and run callback
    while protocol.active
        handle_msg_channel(protocol, data_handler)
        handle_conn_channel(protocol)
        yield()
    end
end

"""
    handle_msg_channel(protocol::MQTTProtocol, data_handler::Function)

Check `protocol.msg_channel`` for new messages and forward their contents to the `data_handler`.
"""
function handle_msg_channel(protocol::MQTTProtocol, data_handler::Function)
    # handle incoming content messages
    while !isempty(protocol.msg_channel)
        msg = take!(protocol.msg_channel)
        topic = msg.topic
        message = msg.payload

        # guaranteed to be a key in the dict unless something went seriously wrong on registration
        @spawnlog data_handler(message, topic; receivers=protocol.topic_to_aid[topic])
    end
end

"""
    handle_conn_channel(protocol::MQTTProtocol)

Check `protocol.conn_chnnel` for new messages and update the protocols connection status accordingly.
"""
function handle_conn_channel(protocol::MQTTProtocol)
    # handle incoming connection status updates
    while !isempty(protocol.conn_channel)
        conncb = take!(protocol.conn_channel)

        if conncb.val == 1
            protocol.connected = true
        elseif conncb.val == 0
            protocol.connected = false
        end
    end
end

"""
    send(protocol::MQTTProtocol, destination::String, message::Any)

Send a `message` to topic `destination` on the clients MQTT broker. 

# Returns
Return value and message id from MQTT library.
"""
function send(protocol::MQTTProtocol, destination::String, message::Any)
    publish(protocol.client, destination, message)
end

"""
    id(protocol::MQTTProtocol)

Return the name the client is registered with at its broker.
"""
function id(protocol::MQTTProtocol)
    return protocol.client.id
end

"""
    subscribe(protocol::MQTTProtocol, topic::String; qos::Int=1)

Subscribe the MQTT client of the `protocol` to `topic` with the given `qos` setting.

# Returns 
The Mosquitto error code and the message id.
"""
function subscribe(protocol::MQTTProtocol, topic::String; qos::Int=1)
    Mosquitto.subscribe(protocol.client, topic; qos=qos)
end

"""
    close(protocol::MQTTProtocol)

Disconnect the client from the broker and stop the message loop.
"""
function close(protocol::MQTTProtocol)
    if protocol.connected
        disconnect(protocol.client)
        Mosquitto.loop_stop(protocol.client)
    end

    protocol.active = false
end

"""
    parse_id(_::MQTTProtocol, id::Any)::String

Return the `id` of the protocol as string (for compliance with container core).
"""
function parse_id(_::MQTTProtocol, id::Any)::String
    return string(id)
end


"""
    notify_register(protocol::MQTTProtocol, aid::String; kwargs...)

Notify the `protocol` MQTT client that a new agent with `aid` has been registered. 

Registration expects a kwarg `topics` to subscribe the agent to. 
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
