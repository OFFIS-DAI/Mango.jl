module AgentRole
export Role,
    handle_message, handle_event, RoleContext, @role, @shared, subscribe_message, subscribe_send, bind_context, emit_event, get_model, subscribe_event, address

using ..AgentAPI
import ..AgentAPI.send_message, ..AgentAPI.address
import ..Mango: schedule
using ..Mango


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
ROLE_BASELINE_FIELDS::Vector = [:(context::Union{RoleContext,Nothing}),
                                :(shared_vars::Vector{Any})]

ROLE_BASELINE_DEFAULTS::Vector = [
    () -> nothing,
    () -> Vector()
]

"""
Macro for defining an role struct. Expects a struct definition
as argument.
    
The macro does 3 things:
1. It adds all baseline fields, defined in ROLE_BASELINE_FIELDS
   (the role context)
2. It adds the supertype `Role` to the given struct.
3. It defines a default constructor, which assigns all baseline fields
   to predefined default values. As a result you can (and should) create 
   a role using only the exclusive fields.

For example the usage could like this.
```julia
@role struct MyRole
    my_own_field::String
end

# results in

mutable struct MyRole <: Agent
    # baseline fields...
    my_own_field::String
end
MyRole(my_own_field) = MyRole(baseline fields defaults..., my_own_field)

# so youl would construct your role like this

my_roel = MyRole("own value")
```
"""
macro role(struct_def)
    Base.remove_linenums!(struct_def)
    
    struct_name = struct_def.args[2]
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
            field = struct_field.args[3]
            field_name = field.args[1]
            field_type = field.args[2]
            new_expr_decl = Expr(:(::), field_name, field_type)
            push!(new_struct_fields, new_expr_decl)
            push!(shared_names, Expr(:tuple, String(field_name), field_type))
            deleteat!(modified_struct_fields, i)
        end
    end
    struct_fields = modified_struct_fields
    
    # Create the new struct definition
    new_struct_def = Expr(
        :struct,
        true,
        Expr(:(<:), struct_name, :(Role)),
        Expr(:block, cat(struct_fields, new_struct_fields, dims=(1,1))...),
    )

    # Creates a constructor, which will assign nothing to all baseline fields, therefore requires you just to call it with the your fields
    # f.e. @role MyRole own_field::String end, can be constructed using MyRole("MyOwnValueFor own_field").
    new_fields = [
        field for field in struct_fields[1+length(ROLE_BASELINE_FIELDS):end] if
        typeof(field) != LineNumberNode
    ]
    new_values = [i == 2 ? Expr(:vect, shared_names...) : Expr(:call, default) for (i, default) in enumerate(ROLE_BASELINE_DEFAULTS)]
    new_struct_values = [Expr(:call, field.args[2]) for field in new_struct_fields]
    new_values = cat(new_values, new_struct_values, dims=(1,1))

    default_constructor_def = Expr(
        :(=),
        Expr(:call, struct_name, new_fields...),
        Expr(
            :call,
            struct_name,
            new_values...,
            new_fields...,
        ),
    )

    esc(Expr(:block, new_struct_def, default_constructor_def))
end

"""
Mark the field as shared across roles, this will implicitly 
"""
macro shared(field_declaration)
    return esc(field_declaration)
end

"""
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
Return the context of role
"""
function context(role::Role)
    return role.context
end

"""
Hook-in function, which will be called on shutdown of the roles
agent.
"""
function on_shutdown(role::Role)
    # default nothing
end

"""
Subscribe a message handler function (it need to have the signature (role, message, meta))
to the message dispatching. This handler function will be called everytime the given
condition function (message, meta -> boolean) evaluates to true when a message arrives
at the roles agent.
"""
function subscribe_message(role::Role, handler::Function, condition::Function)
    subscribe_message_handle(role.context.agent, role, handler, condition)
end

"""
Subscribe a send_message hook in function (signature, (role, content, receiver_id, receiver_addr; kwargs...)) to the
message sending. The hook in function will be called every time a message is sent by the agent.
"""
function subscribe_send(role::Role, handler::Function)
    subscribe_send_handle(role.context.agent, role, handler)
end

"""
Subscribe to specific types of events.
"""
function subscribe_event(role::Role, event::DataType, event_handler::Any, condition::Function)
    subscribe_event_handle(role.context.agent, role, event, event_handler; condition=condition)
end

"""
Emit an event to their subscriber
"""
function emit_event(role::Role, event::Any; event_type::Any=nothing)
    emit_event_handle(role.context.agent, role, event, event_type=event_type)
end

"""
Get a shared model from the pool. If the model does not exist yet, it will be created.
Only types with default constructor are allowed!
"""
function get_model(role::Role, type::DataType)
    get_model_handle(role.context.agent, type)
end

"""
Delegates to the scheduler `Scheduler`
"""
function schedule(f::Function, role::Role, data::TaskData)
    schedule(f, role.context.agent, data)
end

"""
Get AgentAddress of the parent agent
"""
function address(role::Role)
    return address(role.context.agent)
end

"""
Send a message using the context to the agent with the receiver id `receiver_id` at the address `receiver_addr`. 
This method will always set a sender_id. Additionally, further keyword arguments can be defines to fill the 
internal meta data of the message.
"""
function send_message(
    role::Role,
    content::Any,
    agent_adress::AgentAddress;
    kwargs...,
)
    return send_message(role.context.agent, content, agent_adress; kwargs...)
end

end
