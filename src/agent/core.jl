export @agent,
	AgentContext,
	AgentRoleHandler,
	handle_message,
	add,
	schedule,
	stop_and_wait_for_all_tasks,
	shutdown,
	on_ready,
	on_start,
	roles,
	forward_to,
	add_forwarding_rule,
	delete_forwarding_rule,
	ForwardingRule

using UUIDs

using Dates: Dates

FORWARDED_FROM_ADDR = "forwarded_from_address"
FORWARDED_FROM_ID = "forwarded_from_id"

"""
Context of the agent. Represents the environment for the specific agent. Therefore it includes a 
connection to the container, including all functions used for interacting with the environment
for the agent.
"""
struct AgentContext
	container::ContainerInterface
end

"""
Internal data regarding the roles.
"""
struct AgentRoleHandler
	roles::Vector{Role}
	handle_message_subs::Vector{Tuple{Role, Function, Function}}
	send_message_subs::Vector{Tuple{Role, Function}}
	event_subs::Dict{Any, Vector{Tuple{Role, Function, Function}}}
	models::Dict{DataType, Any}
end

struct ForwardingRule
	from_address::AgentAddress
	to_address::AgentAddress
	forward_replies::Bool
end

"""
All baseline fields added by the @agent macro are listed in this vector.
They are added in the same order defined here.
"""
AGENT_BASELINE_FIELDS::Vector = [
	:(lock::ReentrantLock),
	:(context::Union{Nothing, AgentContext}),
	:(role_handler::Union{AgentRoleHandler}),
	:(scheduler::AbstractScheduler),
	:(aid::Union{Nothing, String}),
	:(transaction_handler::Dict{String, Tuple}),
	:(forwarding_rules::Vector{ForwardingRule}),
]

"""
Default values for the baseline fields. These have to be defined using
an anonymous functions. Always need to have the same length as 
AGENT_BASELINE_FIELDS.
"""
AGENT_BASELINE_DEFAULTS::Vector = [
	() -> ReentrantLock(),
	() -> nothing,
	() -> AgentRoleHandler(Vector(), Vector(), Vector(), Dict(), Dict()),
	() -> Scheduler(),
	() -> nothing,
	() -> Dict{String, Tuple}(),
	() -> Vector{ForwardingRule}(),
]

"""
Macro for defining an agent struct. Expects a struct definition
as argument.
	
The macro does 3 things:
1. It adds all baseline fields, defined in AGENT_BASELINE_FIELDS
   (the agent context `context`, the role handler `role_handler`, and the `aid`)
2. It adds the supertype `Agent` to the given struct.
3. It defines a default constructor, which assigns all baseline fields
   to predefined default values. As a result you can (and should) create 
   an agent using only the exclusive fields.

For example the usage could like this.
```julia
@agent struct MyAgent
	my_own_field::String
end

# results in

mutable struct MyAgent <: Agent
	# baseline fields...
	my_own_field::String
end
MyAgent(my_own_field) = MyAgent(baseline fields defaults..., my_own_field)

# so youl would construct your agent like this

my_agent = MyAgent("own value")
```
"""
macro agent(struct_def)
	struct_head = struct_def.args[2]
	struct_name = struct_head
	if typeof(struct_name) != Symbol
		struct_name = struct_head.args[1]
	end
	struct_fields = struct_def.args[3].args

	# Add the agents baseline fields
	for field in reverse(AGENT_BASELINE_FIELDS)
		pushfirst!(struct_fields, field)
	end

	# Create the new struct definition
	new_struct_def = Expr(
		:struct,
		true,
		Expr(:(<:), struct_head, :(Agent)),
		Expr(:block, struct_fields...),
	)

	# Create a constructor, which will assign 'nothing' to all baseline fields, therefore requires you just to call it with the your fields
	# f.e. @agent MyMagent own_field::String end, can be constructed using MyAgent("MyOwnValueFor own_field").
	new_fields = [
		field.args[1] for field in struct_fields[2+length(AGENT_BASELINE_FIELDS):end] if
		typeof(field) != LineNumberNode
	]
	default_constructor_def = Expr(
		:(=),
		Expr(:call, struct_name, new_fields...),
		Expr(
			:block,
			:(),
			Expr(
				:call,
				struct_name,
				[Expr(:call, default) for default in AGENT_BASELINE_DEFAULTS]...,
				new_fields...,
			),
		),
	)

	esc(Expr(:block, new_struct_def, default_constructor_def))
end


function build_forwarded_address_from_meta(meta::AbstractDict)
	return AgentAddress(aid = meta["reply_to_forwarded_from_id"], address = meta["reply_to_forwarded_from_address"], tracking_id = get(meta, TRACKING_ID, nothing))
end

"""
Internal API used by the container to dispatch an incoming message to the agent. 
In this function the message will be handed over to the different handlers in the
agent.
"""
function dispatch_message(agent::Agent, message::Any, meta::AbstractDict)
	# check if auto forwarding is applicable
	sender_addr = get(meta, SENDER_ADDR, nothing)
	sender_id = get(meta, SENDER_ID, nothing)
	forwarded = false
	for rule::ForwardingRule in agent.forwarding_rules
		if rule.from_address.aid == sender_id && rule.from_address.address == sender_addr
			wait(forward_to(agent, message, rule.to_address, meta))
			forwarded = true
		end
		# if reply to a forwarded message and replies shall be forwarded, forward this message to the original sender
		if rule.to_address.address == sender_addr && rule.to_address.aid == sender_id && get(meta, "reply_to_forwarded", false) && rule.forward_replies
			wait(forward_to(agent, message, build_forwarded_address_from_meta(meta), meta))
			forwarded = true
		end
	end
	if forwarded
		return
	end

	lock(agent.lock) do
		# check if part of a transaction
		if haskey(meta, TRACKING_ID) && haskey(agent.transaction_handler, meta[TRACKING_ID])
			caller, response_handler = agent.transaction_handler[meta[TRACKING_ID]]
			delete!(agent.transaction_handler, meta[TRACKING_ID])
			response_handler(caller, message, meta)
		else
			for role in agent.role_handler.roles
				handle_message(role, message, meta)
			end
			for (role, call, condition) in agent.role_handler.handle_message_subs
				if condition(message, meta)
					call(role, message, meta)
				end
			end
			handle_message(agent, message, meta)
		end
	end
end

"""
Defines a function for an agent, which will be called when a message is dispatched
to the agent. This methods will be called with any arriving message (according to
the multiple dispatch of julia).
"""
function handle_message(agent::Agent, message::Any, meta::Any)
	# do nothing by default
end

function notify_start(agent::Agent)
	on_start(agent)
	for role in roles(agent)
		on_start(role)
	end
end

function notify_ready(agent::Agent)
	on_ready(agent)
	for role in roles(agent)
		on_ready(role)
	end
end

"""
Lifecycle Hook-in function called when the container of the agent has been started,
depending on the container type it may not be called (if there is no start at all, 
f.e. the simulation container)
"""
function on_start(agent::Agent)
	# do nothing by default
end

"""
Lifecycle Hook-in function called when the agent system as a whole is ready, the 
hook-in has to be manually activated using notify_ready(container::Container)
"""
function on_ready(agent::Agent)
	# do nothing by default
end

"""
Returns the agent id of the agent.
"""
function aid(agent::Agent)
	return agent.aid
end

"""
Add a role to the agent. This will add the role
to the internal RoleHandler of the agent and it
will bind the RoleContext to the role, which enables
the role to interact with its environment.
"""
function add(agent::Agent, role::Role)
	push!(agent.role_handler.roles, role)
	bind_context(role, RoleContext(agent))
end

"""
Return all roles of the given agent
"""
function roles(agent::Agent)
	return agent.role_handler.roles
end

"""
Will be called on shutdown of the container, in which
the agent is living
"""
function shutdown(agent::Agent)
	for role in agent.role_handler.roles
		shutdown(role)
	end

	stop_and_wait_for_all_tasks(agent.scheduler)
end

"""
Internal implementation of the agent API.
"""
function subscribe_message_handle(
	agent::Agent,
	role::Role,
	condition::Function,
	handler::Function,
)
	push!(agent.role_handler.handle_message_subs, (role, condition, handler))
end

"""
Internal implementation of the agent API.
"""
function subscribe_send_handle(agent::Agent, role::Role, handler::Function)
	push!(agent.role_handler.send_message_subs, (role, handler))
end

"""
Internal implementation of the agent API.
"""
function subscribe_event_handle(agent::Agent, role::Role, event_type::Any, event_handler::Function; condition::Function = (a, b) -> true)
	if !haskey(agent.role_handler.event_subs, event_type)
		agent.role_handler.event_subs[event_type] = Vector()
	end
	push!(agent.role_handler.event_subs[event_type], (role, condition, event_handler))
end

"""
Internal implementation of the agent API.
"""
function emit_event_handle(agent::Agent, src::Role, event::Any; event_type::Any = nothing)
	key = !isnothing(event_type) ? event_type : typeof(event)
	if haskey(agent.role_handler.event_subs, key)
		for (role, condition, func) in agent.role_handler.event_subs[key]
			if condition(src, event)
				func(role, src, event, event_type)
			end
		end
	end
	for role in roles(agent)
		handle_event(role, src, event, event_type = event_type)
	end
end

"""
Internal implementation of the agent API.
"""
function get_model_handle(agent::Agent, type::DataType)
	if !haskey(agent.role_handler.models, type)
		agent.role_handler.models[type] = type()
	end
	return agent.role_handler.models[type]
end

"""
Add a rule for message forwarding.

After calling the agent will auto-forward every message coming from `from_addr` to
`to_address`. If forward_replies is set, all replies from `to_address` are forwarded
back to `from_addr`.
"""
function add_forwarding_rule(agent::Agent, from_addr::AgentAddress, to_address::AgentAddress, forward_replies::Bool)
	push!(agent.forwarding_rules, ForwardingRule(from_addr, to_address, forward_replies))
end

"""
Delete an added forwarding rule. If `to_address` is not set, all rules are removed matching
`from_addr`. If it set, both addresses need to match.
"""
function delete_forwarding_rule(agent::Agent, from_addr::AgentAddress, to_address::Union{Nothing, AgentAddress})
	for i in length(agent.forwarding_rules):-1:1
		rule = agent.forwarding_rules[i]
		if rule.from_address == from_addr && (isnothing(to_address) || to_address == rule.to_address)
			deleteat!(agent.forwarding_rules, i)
		end
	end
end

"""
Delegates to the scheduler `Scheduler`
"""
function schedule(f::Function, agent::Agent, data::TaskData)
	schedule(f, agent.scheduler, data)
end

"""
Delegates to the scheduler `Scheduler`
"""
function stop_and_wait_for_all_tasks(agent::Agent)
	stop_and_wait_for_all_tasks(agent.scheduler)
end

"""
Delegates to the scheduler `Scheduler`
"""
function stop_task(agent::Agent, t::Task)
	stop_task(agent.scheduler, t)
end

"""
Delegates to the scheduler `Scheduler`
"""
function wait_for_all_tasks(agent::Agent)
	wait_for_all_tasks(agent.scheduler)
end

"""
Delegates to the scheduler `Scheduler`
"""
function stop_all_tasks(agent::Agent)
	stop_all_tasks(agent.scheduler)
end

"""
Shorter Alias
"""
function address(agent::Agent)
	addr::Any = nothing
	if !isnothing(agent.context)
		addr = protocol_addr(agent.context.container)
	end
	return AgentAddress(aid = aid(agent), address = addr)
end

"""
Send a message using the context to the agent with the receiver id `receiver_id` at the address `receiver_addr`. 
This method will always set a sender_id. Additionally, further keyword arguments can be defines to fill the 
internal meta data of the message.
"""
function send_message(
	agent::Agent,
	content::Any,
	agent_adress::AgentAddress;
	kwargs...,
)
	for (role, handler) in agent.role_handler.send_message_subs
		handler(role, content, agent_adress; kwargs...)
	end
	return send_message(
		agent.context.container,
		content,
		agent_adress,
		agent.aid;
		kwargs...,
	)
end

function send_message(
	agent::Agent,
	content::Any,
	mqtt_address::MQTTAddress;
	kwargs...,
)
	for (role, handler) in agent.role_handler.send_message_subs
		handler(role, content, mqtt_address; kwargs...)
	end
	return send_message(
		agent.context.container,
		content,
		mqtt_address;
		kwargs...,
	)
end

"""
Send a message using the context to the agent with the receiver id `receiver_id` at the address `receiver_addr`. 
This method will always set a sender_id. Additionally, further keyword arguments can be defines to fill the 
internal meta data of the message.

Furthermore, message sent with this method will be wrapped in a data object which annotates the message with a 
transactional id, to be able to track this specific agent discussion. For this it is possible to define a response_handler,
to which a functin can be assigned, which handles the answer to this message call. To continue the conversation the
transaction id has to be tr by kwargs in the response handler 
"""
function send_tracked_message(
	agent::Agent,
	content::Any,
	agent_address::AgentAddress;
	response_handler::Union{Function, Nothing} = nothing,
	calling_object::Any = nothing,
	kwargs...,
)
	tracking_id = string(uuid1())
	if !isnothing(agent_address.tracking_id)
		tracking_id = agent_address.tracking_id
	end
	if !isnothing(response_handler)
		caller = agent
		if !isnothing(calling_object)
			caller = calling_object
		end
		agent.transaction_handler[tracking_id] = (caller, response_handler)
	end
	return send_message(agent, content, AgentAddress(agent_address.aid, agent_address.address, tracking_id); kwargs...)
end

"""
Convenience method for sending tracked messages with response handler to the answer.

Sends a tracked message with a required response_handler to enable to use the syntax
```
send_and_handle_answer(...) do agent, message, meta
	# handle the answer
end
```
"""
function send_and_handle_answer(
	response_handler::Function,
	agent::Agent,
	content::Any,
	agent_address::AgentAddress;
	calling_object::Any = nothing,
	kwargs...)
	return send_tracked_message(agent, content, agent_address; response_handler = response_handler,
		calling_object = calling_object, kwargs...)
end

"""
Convenience method to reply to a received message using the meta the agent received. This reduces the regular send_message as response
`send_message(agent, "Pong", AgentAddress(aid=meta["sender_id"], address=meta["sender_addr"]))`
to
`reply_to(agent, "Pong", meta)`

Furthermore it guarantees that agent address (including the tracking id, which is part of the address!) is correctly passed to the mango
container.
"""
function reply_to(agent::Agent,
	content::Any,
	received_meta::AbstractDict;
	response_handler::Union{Function, Nothing} = nothing,
	calling_object::Any = nothing,
	kwargs...)
	return send_tracked_message(agent, content, AgentAddress(received_meta[SENDER_ID],
			received_meta[SENDER_ADDR],
			get(received_meta, TRACKING_ID, nothing));
		response_handler = response_handler,
		calling_object = calling_object,
		reply = true,
		reply_to_forwarded = get(received_meta, "forwarded", false),
		reply_to_forwarded_from_address = get(received_meta, FORWARDED_FROM_ADDR, nothing),
		reply_to_forwarded_from_id = get(received_meta, FORWARDED_FROM_ID, nothing),
		kwargs...)
end

"""
Forward the message to a specific agent using the metadata received on handling
the message. This method essentially simply calls send_message on the input given, but
also adds and fills the correct metadata fields to mark the message as forwarded. 

For this the following is set.
'forwarded=`true`',
'forwarded_from_address=`address of the original sender`',
'forwarded_from_id=`id of the original sender`'
"""
function forward_to(agent::Agent,
	content::Any,
	forward_to_address::AgentAddress,
	received_meta::AbstractDict;
	kwargs...)
	return send_message(agent, content, forward_to_address; forwarded = true,
		forwarded_from_address = received_meta[SENDER_ADDR],
		forwarded_from_id = received_meta[SENDER_ID])
end
