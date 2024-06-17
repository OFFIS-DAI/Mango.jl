export MQTTProtocol,
    send,
    init,
    close,
    id,
    has_message,
    get_messages_channel,
    disconnect,
    subscribe

using Mosquitto
using Sockets: InetAddr

# one protocol one broker for now?
# TODO TLS and connection handling for that

mutable struct MQTTProtocol <: Protocol{String}
    client::Client
    broker_addr::InetAddr
    connected::Bool
    msg_channel::Channel
    conn_channel::Channel

    function MQTTProtocol(client_id::String, broker_addr::InetAddr)
        # Have to cast types for the MQTT client constructor.
        # TODO: maybe suggest a constructor using InetAddr to the Mosquitto repo?
        c = Client(string(broker_addr.host), Int64(broker_addr.port); id=client_id)
        msg_channel = get_messages_channel(c)
        conn_channel = get_connect_channel(c)
        return new(c, broker_addr, false, msg_channel, conn_channel)
    end
end

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
                    Threads.@spawn data_handler(message, topic)
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

function send(protocol::MQTTProtocol, destination::String, message::Any)
    publish(protocol.client, destination, message)
end

function id(protocol::MQTTProtocol)
    return protocol.client.id
end

function is_connected(protocol::MQTTProtocol)::Bool
    connect_channel = get_connect_channel(protocol.client)

    while !isempty(connect_channel)
        conncb = take!(connect_channel)

        if conncb.val == 1
            protocol.connected = true
        elseif conncb.val == 0
            protocol.connected = false
        end
    end

    return protocol.connected
end

function subscribe(protocol::MQTTProtocol, topic::String; qos::Int=1)
    Mosquitto.subscribe(protocol.client, topic; qos)
end

function close(protocol::MQTTProtocol)
    disconnect(protocol.client)
    Mosquitto.loop_stop(protocol.client)
end

function parse_id(_::MQTTProtocol, id::Any)::String
    return string(id)
end