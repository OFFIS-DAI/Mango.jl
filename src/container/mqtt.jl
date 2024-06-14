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

    function MQTTProtocol(client_id::String, broker_addr::InetAddr)
        return new(Client(; id=client_id), broker_addr)
    end
end

function init(protocol::MQTTProtocol, stop_check::Function, data_handler::Function)

end

function send(protocol::MQTTProtocol, destination::String, message::Any)
    publish(protocol.client, destination, message)
end

function id(protocol::MQTTProtocol)
    return protocol.client.id
end

function is_connected(protocol::MQTTProtocol)::Bool

end

function has_message(protocol::MQTTProtocol)::Bool
    msg_channel = get_messages_channel(protocol.client)
    return !isempty(msg_channel)
end

function get_messages_channel(protocol::MQTTProtocol)
    return get_messages_channel(protocol.client)
end

function subscribe(protocol::MQTTProtocol, topic::String; qos::Int=1)
    subscribe(protocol.client, topic; qos)
end

function loop_forever(protcol::MQTTProtocol)
    Mosquitto.loop_forever2(protocol.client)
end

function close(protocol::MQTTProtocol)
    disconnect(protocol.client)
    loop(protocol.client)
end