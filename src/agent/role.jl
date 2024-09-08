export Role,
    RoleContext,
    handle_event,
    @role,
    @shared,
    subscribe_message,
    subscribe_send,
    bind_context,
    emit_event,
    get_model,
    subscribe_event,
    setup,
    on_global_event


"""
Defines the type Role, which is the common base types for all roles in mango.

A Role is a bundled behavivor of an agent, which shall fulfill exactly one 
responsibility of an agent - the role. Technically speaking roles are the
way to implement the composition pattern for agents, and to introduce
modular archetypes, which shall be reused in different contexts. 
"""
abstract type Role end

"""
The `RoleContext` connects the role with its environment, which is
mostly its agents. This is abstracted using the `AgentInterface`.
"""
mutable struct RoleContext
    agent::AgentInterface
end

"""
List of all baseline fields of every role, which will be inserted
by the macro @role.
"""
ROLE_BASELINE_FIELDS::Vector = [:(context::Union{RoleContext,Nothing} = nothing),
    :(shared_vars::Vector{Any} = Vector())]


"""
Macro for defining a role struct. Expects a struct definition
as argument.
	
The macro does 3 things:
1. It adds all baseline fields, defined in `ROLE_BASELINE_FIELDS`
   (the role context)
2. It adds the supertype `Role` to the given struct.
3. It applies [`@with_def`](@ref) for default construction, the baseline fields are assigned
   to default values

For example the usage could like this.
```julia
@role struct MyRole
	my_own_field::String
end

# results in

@with_def mutable struct MyRole <: Role
	# baseline fields...
	my_own_field::String
    my_own_field_with_default::String = "Default"
end

# so youl would construct your role like this

my_roel = MyRole("own value", my_own_field_with_default="OtherValue")
```
"""
macro role(struct_def)
    Base.remove_linenums!(struct_def)

    struct_head = struct_def.args[2]
    struct_name = struct_head
    if typeof(struct_name) != Symbol
        struct_name = struct_head.args[1]
    end
    struct_fields = struct_def.args[3].args

    # Add the roles baseline fields
    for field in reverse(ROLE_BASELINE_FIELDS)
        pushfirst!(struct_fields, field)
    end

    # Remove all @shared declarations from the struct definition
    shared_names = []
    new_struct_fields = []
    modified_struct_fields = Vector(struct_fields)
    for i in length(struct_fields):-1:1
        struct_field = struct_fields[i]
        name = struct_field.args[1]
        if name == Symbol("@shared")
            struct_field = struct_fields[i+1]
            field_name = struct_field.args[1]
            field_type = struct_field.args[2]
            # evaluates to field_name::field_type = field_type()
            new_expr_decl = Expr(:(=), Expr(:(::), field_name, field_type), Expr(:call, Symbol(field_type)))
            push!(new_struct_fields, new_expr_decl)
            push!(shared_names, Expr(:tuple, String(field_name), field_type))
            deleteat!(modified_struct_fields, i + 1)
            deleteat!(modified_struct_fields, i)
        end
    end
    struct_fields = modified_struct_fields

    # Create the new struct definition
    new_struct_def = Expr(:macrocall, Symbol("@with_def"), LineNumberNode(0, Symbol("none")), Expr(
        :struct,
        true,
        Expr(:(<:), struct_head, :(Role)),
        Expr(:block, cat(struct_fields, new_struct_fields, dims=(1, 1))...),
    ))

    esc(Expr(:block, new_struct_def))
end

"""
Mark the field as shared across roles. 

This only works on structs with empty default constructor. Internally the marked field will be initialized
with a model created by [`get_model`](@ref). The model will be set when the Role is added to an agent.

# Example
```julia
@kwdef struct Model
    field::Int = 0
end
@role struct MyRole
    @shared
    my_model::Model # per agent the exact same in every agent.
end
```
"""
macro shared(field_declaration)
    return esc(field_declaration)
end

"""
    setup(role::Role)

Hook-in function to setup the role, after it has been
added to its agent.
"""
function setup(role::Role)
    # default nothing
end

"""
Default function for arriving messages, which get dispatched to the role.
This function will be called for every message arriving at the agent of the role.
"""
function handle_message(role::Role, message::Any, meta::Any)
    # do nothing by default
end

"""
    handle_event(role::Role, src::Role, event::Any; event_type::Any)

Default function for arriving events, which get dispatched to the role.
"""
function handle_event(role::Role, src::Role, event::Any; event_type::Any)
    # do nothing by default
end

"""
Internal function, used to initialize to role for a specified agent
"""
function bind_context(role::Role, context::RoleContext)
    role.context = context
    for shared_var in role.shared_vars
        shared_model = get_model(role, eval(shared_var[2]))
        setproperty!(role, Symbol(shared_var[1]), shared_model)
    end
    setup(role)
end

"""
    context(role::Role)

Return the context of role
"""
function context(role::Role)
    return role.context
end

function shutdown(role::Role)
    # default nothing
end

function on_start(role::Role)
    # do nothing by default
end

function on_ready(role::Role)
    # do nothing by default
end

"""
    subscribe_message(role::Role, handler::Function, condition::Function)

Subscribe a message handler function (it need to have the signature (role, message, meta))
to the message dispatching. This handler function will be called everytime the given
condition function ((message, meta) -> boolean) evaluates to true when a message arrives
at the roles agent.
"""
function subscribe_message(role::Role, handler::Function, condition::Function)
    subscribe_message_handle(role.context.agent, role, handler, condition)
end

"""
    subscribe_send(role::Role, handler::Function)

Subscribe a `send_message` hook in function (signature, (role, content, receiver_id, receiver_addr; kwargs...)) to the
message sending. The hook in function will be called every time a message is sent by the agent.
"""
function subscribe_send(role::Role, handler::Function)
    subscribe_send_handle(role.context.agent, role, handler)
end

"""
    subscribe_event(role::Role, event_type::Any, event_handler::Any, condition::Function)

Subscribe to specific types of events. 

The types of events are determined by the `condition` function (accepting `src` and `event`) and 
by the `event_type`.

# Example
```julia
struct MyEvent end
function custom_handler(role::Role, src::Role, event::Any, event_type::Any)
    # do your thing
end
subscribe_event(my_role, MyEvent, custom_handler, (src, event) -> aid(src) == "agent0")
```
"""
function subscribe_event(role::Role, event_type::Any, event_handler::Any, condition::Function=(a, b) -> true)
    subscribe_event_handle(role.context.agent, role, event_type, event_handler; condition=condition)
end

"""
    emit_event(role::Role, event::Any; event_type::Any=nothing)

Emit an event to their subscriber.
"""
function emit_event(role::Role, event::Any; event_type::Any=nothing)
    emit_event_handle(role.context.agent, role, event, event_type=event_type)
end

"""
    get_model(role::Role, type::DataType)

Get a shared model from the pool. If the model does not exist yet, it will be created.
Only types with default constructor are allowed!

# Example
```julia
@kwdef struct ExampleModel
    my_field::Int = 0
end
role = ExampleRole()
model::ExampleModel = get_model(role, ExampleModel)
model.my_field = 1
model2::ExampleModel = get_model(role, ExampleModel)
# model == model2, it will also be the same for every role!
```
"""
function get_model(role::Role, type::DataType)
    get_model_handle(role.context.agent, type)
end

function schedule(f::Function, role::Role, data::TaskData)
    schedule(f, role.context.agent, data)
end

function aid(role::Role)
    return address(role.context.agent).aid
end

function address(role::Role)
    return address(role.context.agent)
end

function add_forwarding_rule(role::Role, from_addr::AgentAddress, to_address::AgentAddress, forward_replies::Bool)
    add_forwarding_rule(role.context.agent, from_addr, to_address, forward_replies)
end

function delete_forwarding_rule(role::Role, from_addr::AgentAddress, to_address::Union{Nothing,AgentAddress})
    delete_forwarding_rule(role.context.agent, from_addr, to_address)
end

function send_message(
    role::Role,
    content::Any,
    agent_adress::AgentAddress;
    kwargs...,
)
    return send_message(role.context.agent, content, agent_adress; kwargs...)
end


function send_tracked_message(
    role::Role,
    content::Any,
    agent_adress::AgentAddress;
    response_handler::Function=(role, message, meta) -> nothing,
    kwargs...,
)
    return send_tracked_message(role.context.agent, content, agent_adress; response_handler=response_handler, calling_object=role, kwargs...)
end

function send_and_handle_answer(
    response_handler::Function,
    role::Role,
    content::Any,
    agent_address::AgentAddress;
    kwargs...)
    return send_and_handle_answer(response_handler, role.context.agent, content, agent_address;
        calling_object=role, kwargs...)
end

function reply_to(role::Role,
    content::Any,
    received_meta::AbstractDict;
    response_handler::Function=(agent, message, meta) -> nothing,
    kwargs...)
    return reply_to(role.context.agent, content, received_meta; response_handler=response_handler, calling_object=role, kwargs...)
end

function forward_to(role::Role,
    content::Any,
    forward_to_address::AgentAddress,
    received_meta::AbstractDict;
    kwargs...)
    return forward_to(role.context.agent, content, forward_to_address, received_meta; kwargs...)
end

"""
    on_global_event(role::Role, event::Any)

Handle global event. See [`emit_global_event`](@ref).
"""
function on_global_event(role::Role, event::Any)
    # to be overridden
end