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
	topic_to_aid::Dict{String, Vector{String}}

	function MQTTProtocol(client_id::String, broker_addr::InetAddr)
		# Have to cast types for the MQTT client constructor.
		c = Client(string(broker_addr.host), Int64(broker_addr.port); id = client_id)
		msg_channel = get_messages_channel(c)
		conn_channel = get_connect_channel(c)
		return new(c, broker_addr, false, false, msg_channel, conn_channel, Dict{String, Vector{String}}())
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
Endlessly loops over incoming messages on the msg_channel and conn_channel 
and processes their contents. 
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
Check msg_channel for new messages and forward their contents to the data_handler.
"""
function handle_msg_channel(protocol::MQTTProtocol, data_handler::Function)
	# handle incoming content messages
	while !isempty(protocol.msg_channel)
		msg = take!(protocol.msg_channel)
		topic = msg.topic
		message = msg.payload

		# guaranteed to be a key in the dict unless something went seriously wrong on registration
		@spawnlog data_handler(message, topic; receivers = protocol.topic_to_aid[topic])
	end
end

"""
Check conn_chnnel for new messages and update the protocols connection status accordingly.
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
Subscribe the MQTT client of the protocol to `topic`.
"""
function subscribe(protocol::MQTTProtocol, topic::String; qos::Int = 1)
	Mosquitto.subscribe(protocol.client, topic; qos)
end

"""
Disconnect the client from the broker and stop the message loop.
"""
function close(protocol::MQTTProtocol)
	if protocol.connected
		disconnect(protocol.client)
		Mosquitto.loop_stop(protocol.client)
	end

	protocol.active = false
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
