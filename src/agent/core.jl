module AgentCore
export @agent,
    dispatch_message, AgentRoleHandler, AgentContext, handle_message, add, schedule

using ..Mango
using ..AgentRole
using ..ContainerAPI
import ..ContainerAPI.send_message

import ..AgentAPI.subscribe_handle
import Dates
import ..Mango: schedule, wait_for_all_tasks

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
    handle_message_subs::Vector{Tuple{Role,Function,Function}}
    send_message_subs::Vector{Tuple{Role,Function}}
end

"""
All baseline fields added by the @agent macro are listed in this vector.
They are added in the same order defined here.
"""
AGENT_BASELINE_FIELDS::Vector = [
    :(lock::ReentrantLock),
    :(context::Union{Nothing,AgentContext}),
    :(role_handler::Union{AgentRoleHandler}),
    :(scheduler::Scheduler),
    :(aid::Union{Nothing,String}),
]
"""
Default values for the baseline fields. These have to be defined using
an anonymous functions. Always need to have the same length as 
AGENT_BASELINE_FIELDS.
"""
AGENT_BASELINE_DEFAULTS::Vector = [
    () -> ReentrantLock(),
    () -> nothing,
    () -> AgentRoleHandler(Vector(), Vector(), Vector()),
    () -> Scheduler(Vector()),
    () -> nothing,
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
    struct_name = struct_def.args[2]
    struct_fields = struct_def.args[3].args

    # Add the agents baseline fields
    for field in reverse(AGENT_BASELINE_FIELDS)
        pushfirst!(struct_fields, field)
    end

    # Create the new struct definition
    new_struct_def = Expr(
        :struct,
        true,
        Expr(:(<:), struct_name, :(Agent)),
        Expr(:block, struct_fields...),
    )

    # Create a constructor, which will assign 'nothing' to all baseline fields, therefore requires you just to call it with the your fields
    # f.e. @agent MyMagent own_field::String end, can be constructed using MyAgent("MyOwnValueFor own_field").
    new_fields = struct_fields[2+length(AGENT_BASELINE_FIELDS):end]
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

"""
Internal API used by the container to dispatch an incoming message to the agent. 
In this function the message will be handed over to the different handlers in the
agent.
"""
function dispatch_message(agent::Agent, message::Any, meta::Any)
    lock(agent.lock) do
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

"""
Defines a function for an agent, which will be called when a message is dispatched
to the agent. This methods will be called with any arriving message (according to
the multiple dispatch of julia).
"""
function handle_message(agent::Agent, message::Any, meta::Any)
    # do nothing by default
    @warn "Default handle message was called. This may be a bug."
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
    return agent.roles
end

"""
Will be called on shutdown of the container, in which
the agent is living
"""
function shutdown(agent::Agent)
    for role in agent.roles
        shutdown(role)
    end
end

"""
Internal implemntation of the agent API.
"""
function subscribe_handle(agent::Agent, role::Role, condition::Function, handler::Function)
    push!(agent.role_handler.handle_message_subs, (role, condition, handler))
end

"""
Delegates to the scheduler `Scheduler`
"""
function schedule(
    f::Function,
    agent::Agent,
    data::TaskData,
    scheduling_type::SchedulingType = ASYNC,
)
    schedule(f, agent.scheduler, data, scheduling_type)
end

"""
Delegates to the scheduler `Scheduler`
"""
function wait_for_all_tasks(agent::Agent)
    wait_for_all_tasks(agent.scheduler)
end

"""
Send a message using the context to the agent with the receiver id `receiver_id` at the address `receiver_addr`. 
This method will always set a sender_id. Additionally, further keyword arguments can be defines to fill the 
internal meta data of the message.
"""
function send_message(
    agent::Agent,
    content::Any,
    receiver_id::String,
    receiver_addr::Any = nothing;
    kwargs...,
)
    return ContainerAPI.send_message(
        agent.context.container,
        content,
        receiver_id,
        receiver_addr,
        agent.aid;
        kwargs...,
    )
end

end
