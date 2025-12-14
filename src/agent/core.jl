export @agent,
    AgentContext,
    AgentRoleHandler,
    SystemHandler,
    handle_message,
    handle_unanswered,
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
    ForwardingRule,
    service_of_type,
    add_service!,
    services,
    on_global_event,
    on_agent_event,
    sender_address,
    send_and_handle_answers,
    send_tracked_messages,
    send_messages,
    has_role,
    description,
    name,
    color,
    category,
    update_description,
    AgentDescription,
    uid,
    uuid4

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
    evironment::Environment
end

"""
Internal data regarding the roles.
"""
struct AgentRoleHandler
    roles::Vector{Role}
    handle_message_subs::Vector{Tuple{Role,Function,Function,Union{Nothing,MessagePreprocessor}}}
    send_message_subs::Vector{Tuple{Role,Function}}
    event_subs::Dict{Any,Vector{Tuple{Role,Function,Function}}}
    models::Dict{DataType,Any}
end

struct ForwardingRule
    from_address::AgentAddress
    to_address::AgentAddress
    forward_replies::Bool
end

mutable struct AgentDescription
    aid::Union{Nothing,String}
    name::String
    category::Symbol
    color::Symbol
    uid::UUID
end

struct SystemHandler
    message_subs::Vector{Tuple{Function,Function,Union{Nothing,MessagePreprocessor},Any}}
    event_subs::Dict{Any,Vector{Tuple{Function,Function,Any}}}
    global_event_subs::Vector{Tuple{Function,Function,Any}}
end

"""
All baseline fields added by the @agent macro are listed in this vector.
They are added in the same order defined here.
"""
AGENT_BASELINE_FIELDS::Vector = [
    :(lock::ReentrantLock = ReentrantLock()),
    :(context::Union{Nothing,AgentContext} = nothing),
    :(role_handler::AgentRoleHandler = AgentRoleHandler(Vector(), Vector(), Vector(), Dict(), Dict())),
    :(system_handler::SystemHandler = SystemHandler(Vector(), Dict(), Vector())),
    :(scheduler::AbstractScheduler = Scheduler()),
    :(transaction_handler::Dict{String,Tuple} = Dict{String,Tuple}()),
    :(forwarding_rules::Vector{ForwardingRule} = Vector{ForwardingRule}()),
    :(outgoing::Vector{Tuple} = Vector{Tuple}()),
    :(description::AgentDescription = AgentDescription(nothing, "", :agent, :gray, uuid4())),
    :(services::Dict{DataType,Any} = Dict{DataType,Any}())
]

"""
Macro for defining an agent struct. Expects a struct definition
as argument.
	
The macro does 3 things:
1. It adds all baseline fields, defined in `AGENT_BASELINE_FIELDS`
   (the agent context `context`, the role handler `role_handler`, and the `aid`)
2. It adds the supertype `Agent` to the given struct.
3. It applies [`@with_def`](@ref) for default construction, the baseline fields are assigned
   to default values

# Example
For example the usage could like this.
```julia
@agent struct MyAgent
	my_own_field::String
end

# results in

@with_def mutable struct MyAgent <: Agent
	# baseline fields...
	my_own_field::String
    my_own_field_with_default::String = "Default"
end

# so you would construct your agent like this

my_agent = MyAgent("own value", my_own_field_with_default="OtherValue")
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
    new_struct_def = Expr(:macrocall, Symbol("@with_def"), LineNumberNode(0, Symbol("none")), Expr(
        :struct,
        true,
        Expr(:(<:), struct_head, :(Agent)),
        Expr(:block, struct_fields...),
    ))

    esc(Expr(:block, new_struct_def))
end

Base.show(io::IO, p::Agent) = print(io, "Agent $(aid(p))")

function build_forwarded_address_from_meta(meta::AbstractDict)
    return AgentAddress(aid=meta["reply_to_forwarded_from_id"], address=meta["reply_to_forwarded_from_address"], tracking_id=get(meta, TRACKING_ID, nothing))
end

function handle_transaction_message(agent::Agent, message::Any, meta::AbstractDict)
    caller, response_handler, addrs, msgs, metas = agent.transaction_handler[meta[TRACKING_ID]]
    sender = sender_address_tracked(meta)
    if length(addrs) == 1
        if addrs[1] == sender
            push!(msgs, message)
            push!(metas, meta)
            delete!(agent.transaction_handler, meta[TRACKING_ID])
            if length(msgs) == 1
                response_handler(caller, msgs[1], metas[1])
            else
                response_handler(caller, msgs, metas)   
            end
        else
            @warn "The transaction $(meta[TRACKING_ID]) seems to be polluted, no incoming message from $sender expected!" aid(agent) addrs message msgs
        end
    else
        # length(addrs) always > 0 -> otherwise sending the message would fail in first place.
        deleting = findall(x->x==sender, addrs)
        if length(deleting) != 0
            push!(msgs, message)
            push!(metas, meta)
            deleteat!(addrs, deleting)
        else
            @warn "The transaction $(meta[TRACKING_ID]) seems to be polluted, no incoming message from $sender expected!" aid(agent) addrs message msgs
        end
    end
end

@kwdef struct WaitingMessagePreprocessor <: MessagePreprocessor
    waiting_for_func::Function
    waiting::Dict{AgentAddress,Bool} = Dict() 
end

function init(preprocessor::WaitingMessagePreprocessor, role_or_agent::Union{Role, Agent})
    for addr in preprocessor.waiting_for_func()
        preprocessor.waiting[addr] = true
    end
end

function handle(preprocessor::WaitingMessagePreprocessor, role_or_agent::Union{Role, Agent}, handler::Function, message::Any, meta::AbstractDict)
    sender = sender_address(meta)
    if sender in keys(preprocessor.waiting)
        preprocessor.waiting[sender] = false
    end
    if !any(values(preprocessor.waiting))
        init(preprocessor, role_or_agent)
        handler(role_or_agent, message, meta)
    end
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
        agent.outgoing = []
        return
    end

    lock(agent.lock) do
        # check if part of a transaction
        if haskey(meta, TRACKING_ID) && 
            haskey(agent.transaction_handler, meta[TRACKING_ID]) && 
            haskey(meta, "reply")
            
            handle_transaction_message(agent, message, meta)
        else
            for role in agent.role_handler.roles
                handle_message(role, message, meta)
            end
            for (role, call, condition, preprocessor) in agent.role_handler.handle_message_subs
                if isnothing(preprocessor)
                    if condition(message, meta)
                        call(role, message, meta)
                    end
                else 
                    if condition(message, meta)
                        handle(preprocessor, role, call, message, meta)
                    end
                end
            end
            handle_message(agent, message, meta)
            for (condition, call, preprocessor, caller) in agent.system_handler.message_subs
                if isnothing(preprocessor)
                    if condition(message, meta)
                        call(caller, message, meta)
                    end
                else 
                    if condition(message, meta)
                        handle(preprocessor, agent, call, message, meta)
                    end
                end
            end
        end
        if length(agent.outgoing) < 1
            for role in agent.role_handler.roles
                handle_unanswered(role, message, meta)
            end
            handle_unanswered(agent, message, meta)
        end
        agent.outgoing = []
    end
end

"""
    sender_address(meta::Any)

Extract the sender address from the meta data of a message and return it as `AgentAddress`.
"""
function sender_address(meta::AbstractDict)
    return AgentAddress(aid=meta[SENDER_ID], address=meta[SENDER_ADDR])
end

"""
    sender_address(meta::Any)

Extract the sender address from the meta data of a message and return it as `AgentAddress`.
"""
function sender_address_tracked(meta::AbstractDict)
    return AgentAddress(aid=meta[SENDER_ID], address=meta[SENDER_ADDR], tracking_id=haskey(meta, TRACKING_ID) ? meta[TRACKING_ID] : nothing)
end

"""
    handle_message(agent::Agent, message::Any, meta::Any)

Defines a function for an agent, which will be called when a message is dispatched
to the agent. This methods will be called with any arriving message (according to
the multiple dispatch of julia).
"""
function handle_message(agent::Agent, message::Any, meta::Any)
    # do nothing by default
end

"""
    handle_unanswered(agent::Agent, message::Any, meta::Any)

Defines a function for an agent, which will be called when after a message has been handled 
    without any messages sent while handling. Useful to do something when a incoming message is
    unknown/ensure there is always an answer.
"""
function handle_unanswered(agent::Agent, message::Any, meta::Any)
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
    on_start(agent::Agent)

Lifecycle Hook-in function called when the container of the agent has been started,
depending on the container type it may not be called (if there is no start at all, 
f.e. the simulation container)
"""
function on_start(agent::Agent)
    # do nothing by default
end

"""
    on_ready(agent::Agent)

Lifecycle Hook-in function called when the agent system as a whole is ready, the 
hook-in has to be manually activated using notify_ready(container::Container). If you use
    the `activate` function, it is called automatically.
"""
function on_ready(agent::Agent)
    # do nothing by default
end

function description(agent::Agent)
    return agent.description
end

function aid(agent::Agent)
    return description(agent).aid
end

function name(agent::Agent)
    return description(agent).name
end

function category(agent::Agent)
    return description(agent).category
end

function color(agent::Agent)
    return description(agent).color
end

function uid(agent::Agent)
    return description(agent).uid
end

function update_description(agent::Agent; color::Union{Nothing, Symbol}=nothing, name::Union{Nothing, String}=nothing, category::Union{Nothing, Symbol}=nothing)
    if !isnothing(name)
        description(agent).name = name
    end
    if !isnothing(color)
        description(agent).color = color
    end
    if !isnothing(category)
        description(agent).category = category
    end
end

"""
    add(agent::Agent, role::Role)

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
    roles(agent)

Return all roles of the given agent
"""
function roles(agent::Agent)::Vector{Role}
    return agent.role_handler.roles
end

function has_role(agent::Agent, role_type::DataType)
    for role in roles(agent)
        if role_type == typeof(role)
            return true
        end
    end
    return false
end

"""
    shutdown(agent)

Will be called on shutdown of the container, in which
the agent is living
"""
function shutdown(agent::Agent)
    for role in agent.role_handler.roles
        shutdown(role)
    end

    stop_and_wait_for_all_tasks(agent.scheduler)
end

function subscribe_message_handle(
    agent::Agent,
    role::Role,
    condition::Function,
    handler::Function;
    preprocessor::Union{Nothing,MessagePreprocessor}=nothing,
)
    if !isnothing(preprocessor)
        init(preprocessor, role)
    end
    push!(agent.role_handler.handle_message_subs, (role, condition, handler, preprocessor))
end

function subscribe_message(
    agent::Agent,
    condition::Function,
    handler::Function;
    preprocessor::Union{Nothing,MessagePreprocessor}=nothing,
)
    if !isnothing(preprocessor)
        init(preprocessor, agent)
    end
    _add_system_handle_message_sub(agent, agent, condition, handler; preprocessor=preprocessor)
end

function subscribe_send_handle(agent::Agent, role::Role, handler::Function)
    push!(agent.role_handler.send_message_subs, (role, handler))
end

function subscribe_event_handle(agent::Agent, role::Role, event_type::Any, event_handler::Function; condition::Function=(a, b) -> true)
    if !haskey(agent.role_handler.event_subs, event_type)
        agent.role_handler.event_subs[event_type] = Vector()
    end
    push!(agent.role_handler.event_subs[event_type], (role, condition, event_handler))
end

function emit_event_handle(agent::Agent, src::Role, event::Any; event_type::Any=nothing)
    key = !isnothing(event_type) ? event_type : typeof(event)
    if haskey(agent.role_handler.event_subs, key)
        for (role, condition, func) in agent.role_handler.event_subs[key]
            if condition(src, event)
                func(role, src, event, event_type)
            end
        end
    end
    for role in roles(agent)
        handle_event(role, src, event, event_type=event_type)
    end
    if haskey(agent.system_handler.event_subs, key)
        for (condition, func, caller) in agent.system_handler.event_subs[key]
            if condition(src, event)
                func(caller, src, event, event_type)
            end
        end
    end
end

function get_model_handle(agent::Agent, type::DataType)
    if !haskey(agent.role_handler.models, type)
        agent.role_handler.models[type] = type()
    end
    return agent.role_handler.models[type]
end

"""
    add_forwarding_rule(agent, from_addr::AgentAddress, to_address::AgentAddress, forward_replies::Bool)

Add a rule for message forwarding.

After calling the agent will auto-forward every message coming from `from_addr` to
`to_address`. If forward_replies is set, all replies from `to_address` are forwarded
back to `from_addr`.
"""
function add_forwarding_rule(agent::Agent, from_addr::AgentAddress, to_address::AgentAddress, forward_replies::Bool)
    push!(agent.forwarding_rules, ForwardingRule(from_addr, to_address, forward_replies))
end

"""
    delete_forwarding_rule(agent, from_addr::AgentAddress, to_address::Union{Nothing,AgentAddress})

Delete an added forwarding rule. If `to_address` is not set, all rules are removed matching
`from_addr`. If it set, both addresses need to match.
"""
function delete_forwarding_rule(agent::Agent, from_addr::AgentAddress, to_address::Union{Nothing,AgentAddress})
    for i in length(agent.forwarding_rules):-1:1
        rule = agent.forwarding_rules[i]
        if rule.from_address == from_addr && (isnothing(to_address) || to_address == rule.to_address)
            deleteat!(agent.forwarding_rules, i)
        end
    end
end

"""
    schedule(f::Function, agent::Agent, data::TaskData)

Delegates to the scheduler `Scheduler`
"""
function schedule(f::Function, agent::Agent, data::TaskData)
    schedule(f, agent.scheduler, data)
end

"""
    clock(agent::Agent)

Return clock of the agent.
"""
function clock(agent::Agent)
    return clock(agent.scheduler)
end

"""
    stop_and_wait_for_all_tasks(agent::Agent)

Delegates to the scheduler `Scheduler`
"""
function stop_and_wait_for_all_tasks(agent::Agent)
    stop_and_wait_for_all_tasks(agent.scheduler)
end

"""
    stop_task(agent::Agent, t::Task)

Delegates to the scheduler `Scheduler`
"""
function stop_task(agent::Agent, t::Task)
    stop_task(agent.scheduler, t)
end

"""
    wait_for_all_tasks(agent::Agent)

Delegates to the scheduler `Scheduler`
"""
function wait_for_all_tasks(agent::Agent)
    wait_for_all_tasks(agent.scheduler)
end

"""
    stop_all_tasks(agent::Agent)

Delegates to the scheduler `Scheduler`
"""
function stop_all_tasks(agent::Agent)
    stop_all_tasks(agent.scheduler)
end

function address(agent::Agent)
    addr::Any = nothing
    if !isnothing(agent.context)
        addr = protocol_addr(agent.context.container)
    end
    return AgentAddress(aid=aid(agent), address=addr)
end

function send_messages(
    agent::Agent,
    content::Any,
    agent_addresses::Vector{AgentAddress};
    kwargs...,
)
    push!(agent.outgoing, (content, kwargs))

    for (role, handler) in agent.role_handler.send_message_subs
        for agent_address in agent_addresses
            handler(role, content, agent_address; kwargs...)
        end
    end
    tasks = []
    for agent_address in agent_addresses
        push!(tasks, send_message(
            agent.context.container,
            content,
            agent_address,
            aid(agent);
            kwargs...,
        ))
    end
    return tasks
end

function send_message(
    agent::Agent,
    content::Any,
    agent_address::AgentAddress;
    kwargs...,
)
    return send_messages(agent, content, [agent_address]; kwargs...)[1]
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

function send_tracked_messages(
    agent::Agent,
    content::Any,
    agent_addresses::Vector{AgentAddress};
    response_handler::Union{Function,Nothing}=nothing,
    calling_object::Any=nothing,
    kwargs...,
)
    tracking_id = string(uuid4())
    if !isnothing(agent_addresses[1].tracking_id)
        tracking_id = agent_addresses[1].tracking_id
    end
    addrs = [AgentAddress(addr.aid, addr.address, tracking_id) for addr in agent_addresses]
    if !isnothing(response_handler)
        caller = agent
        if !isnothing(calling_object)
            caller = calling_object
        end
        agent.transaction_handler[tracking_id] = (caller, response_handler, addrs, [], [])
    end
    return send_messages(agent, content, addrs; kwargs...)
end

function send_tracked_message(
    agent::Agent,
    content::Any,
    agent_address::AgentAddress;
    response_handler::Union{Function,Nothing}=nothing,
    calling_object::Any=nothing,
    kwargs...,
)
    return send_tracked_messages(agent, content, [agent_address]; response_handler=response_handler, calling_object=calling_object, kwargs...)[1]
end

function send_and_handle_answers(
    response_handler::Function,
    agent::Agent,
    content::Any,
    agent_addresses::Vector{AgentAddress};
    calling_object::Any=nothing,
    kwargs...)
    return send_tracked_messages(agent, content, agent_addresses; response_handler=response_handler,
        calling_object=calling_object, kwargs...)
end

function send_and_handle_answer(
    response_handler::Function,
    agent::Agent,
    content::Any,
    agent_address::AgentAddress;
    calling_object::Any=nothing,
    kwargs...)
    return send_and_handle_answers(response_handler, agent, content, [agent_address]; calling_object=calling_object, kwargs...)[1]
end

function reply_to(agent::Agent,
    content::Any,
    received_meta::AbstractDict;
    response_handler::Union{Function,Nothing}=nothing,
    calling_object::Any=nothing,
    kwargs...)
    return send_tracked_message(agent, content, AgentAddress(received_meta[SENDER_ID],
            received_meta[SENDER_ADDR],
            get(received_meta, TRACKING_ID, nothing));
        response_handler=response_handler,
        calling_object=calling_object,
        reply=true,
        reply_to_forwarded=get(received_meta, "forwarded", false),
        reply_to_forwarded_from_address=get(received_meta, FORWARDED_FROM_ADDR, nothing),
        reply_to_forwarded_from_id=get(received_meta, FORWARDED_FROM_ID, nothing),
        kwargs...)
end

function forward_to(agent::Agent,
    content::Any,
    forward_to_address::AgentAddress,
    received_meta::AbstractDict;
    kwargs...)
    return send_message(agent, content, forward_to_address; forwarded=true,
        forwarded_from_address=received_meta[SENDER_ADDR],
        forwarded_from_id=received_meta[SENDER_ID])
end

"""
    services(agent)::Dict{DataType,Any}

Return a list of services, which were added to the agent.
"""
function services(agent::Agent)::Dict{DataType,Any}
    return agent.services
end

"""
    service_of_type(agent, type::Type{T}, default=nothing)::Union{T,Nothing} where {T}

Return the current agent service of the type `type`. 

If a default is set, this default service will be added to the agent as service of te type `type. The
function is especially useful if you want to extend the functionality of the agent without
having to change the internals of the agent, as this functions enables the user to add 
arbitrary data to the agent on which functions can be defined.
"""
function service_of_type(agent::Agent, type::Type{T}, default::Union{T,Nothing}=nothing)::Union{T,Nothing} where {T}
    for pair in services(agent)
        if isa(pair[1], type) || pair[1] == type
            return pair[2]
        end
    end
    if !isnothing(default)
        add_service!(agent, default)
    end
    return default
end

"""
    add_service!(agent, service)

Add a service to the agent. Every service can exists exactly one time (stored by type).
"""
function add_service!(agent::Agent, service::Any)
    agent.services[typeof(service)] = service
end

"""
    Base.getindex(agent::T, index::Int) where {T<:Agent}

Return the `index`'th role of the agent.
"""
function Base.getindex(agent::T, index::Int) where {T<:Agent}
    return roles(agent)[index]
end

function Base.getindex(agent::T, index::Type) where {T<:Agent}
    for role in roles(agent)
        if typeof(role) == index
            return role
        end
    end
    throw(ArgumentError("The agent has no role of the type index=$index."))
end

"""
    on_global_event(agent::Agent, event::Any)

Handle global event. See [`emit_global_event`](@ref).
"""
function on_global_event(agent::Agent, clock::Clock, event::Any)
    # to be overridden
end

"""
    on_agent_event(agent::Agent, event::Any)

Handles an agent event. See [`emit_agent_event`](@ref).
"""
function on_agent_event(agent::Agent, clock::Clock, event::Any)
    # to be overridden
end

function dispatch_global_event(agent::Agent, clock::Clock, event::Any)
    on_global_event(agent, clock, event)
    for role in roles(agent)
        on_global_event(role, clock, event)
    end
    for (condition, call, caller) in agent.system_handler.global_event_subs
        if condition(event)
            call(caller, clock, event)
        end
    end
end

function _add_system_handle_message_sub(agent::Agent, caller::Any, filter::Function, handle::Function; preprocessor::Union{Nothing,<:MessagePreprocessor}=nothing)
    push!(agent.system_handler.message_subs, (filter, handle, preprocessor, caller))
end

function _add_system_event_sub(agent::Agent, caller::Any, event_type::Any, filter::Function, handle::Function)
    event_type_subs = get!(agent.system_handler.event_subs, event_type, Vector())
    push!(event_type_subs, (filter, handle, caller))
end

function _add_system_global_event_sub(agent::Agent, caller::Any, filter::Function, handle::Function)
    push!(agent.system_handler.global_event_subs, (filter, handle, caller))
end