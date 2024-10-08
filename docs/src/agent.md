# Agents

Agents are autonomous entities that can perceive their environment, make decisions, and interact with other agents and the system they inhabit. They are the building blocks of Mango.jl, representing the individual entities or actors within a larger system.


## Agent Definition with @agent Macro

To define an agent the [`@agent`](@ref) macro can be used. It simplifies the process of defining an agent struct and automatically adds necessary baseline fields. Here's how you can define an agent:

```@example
using Mango 

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end

# Create an instance of the agent
my_agent = MyAgent("MyValue")
```

The [`@agent`](@ref) macro adds some internal baseline fields to the struct. You can initialize the agent with exclusive fields like `my_own_field` in the example.

## Role Management

Agents can have multiple roles associated with them. Roles can be added using the [`add`](@ref) function, allowing the agent to interact with its environment based on different roles. Here's how you can add roles to an agent:

```@example
using Mango

# Define your role struct using @role macro
@role struct MyRole
    my_own_field::String
end

# Assume you have already defined roles using Mango.AgentRole module
role1 = MyRole("Role1")
role2 = MyRole("Role2")

# Define your agent struct using @agent macro
@agent struct MyContainerAgent end

# Create an instance of the agent
my_agent = MyContainerAgent()

# Add roles to the agent
add(my_agent, role1)
add(my_agent, role2)

# Now you can interact with the roles as neededs
```

As this can be clunky at some time, there is the possibility to create an agent using only roles and add it to the container using [`add_agent_composed_of`](@ref) or without a container [`agent_composed_of`](@ref).

```@example
using Mango

c = create_tcp_container()

@role struct RoleA end
@role struct RoleB end
@role struct RoleC end

# internally an empty agent definition is used, the roles are added and the agent
# is added to the given container
created_agent = add_agent_composed_of(c, RoleA(), RoleB(), RoleC())
```

For more information on roles, take a look at [Role definition](@ref)

## Message Handling

Agents and Roles can handle incoming messages through the [`handle_message`](@ref) function. By default, it does nothing, but you can override it to define message-specific behavior. You can also add custom message handlers for specific roles using the [`subscribe_message`](@ref) function. Here's how to handle messages:

```@example
using Mango

@agent struct MySecondContainerAgent end
@role struct MyHandlingRole end

# Override the default handle_message function for custom behavior
function Mango.handle_message(agent::MySecondContainerAgent, message::Any, meta::Any)
    println("Received message @agent: ", message)
end
# Override the default handle_message function for custom behavior
function Mango.handle_message(role::MyHandlingRole, message::Any, meta::Any)
    println("Received message @role: ", message)
end

# Use the express API to show the effect
run_with_tcp(1, agent_composed_of(MyHandlingRole(), base_agent=MySecondContainerAgent())) do cl
    wait(send_message(cl[1], "Message", address(cl[1][1])))
    sleep(0.1)
end
```

Besides the ability to handle messages, there also must be a possibility to send messages. This is implemented using the [`send_message`](@ref) function, defined on roles and agents.

```@example
using Mango

# Define your agent struct using @agent macro
@agent struct MySendingAgent
    my_own_field::String
end
@role struct MySendingRole
    my_own_field::String
end

agent = MySendingAgent("")
role = MySendingRole("")

run_with_tcp(1, agent_composed_of(role, base_agent=agent), PrintingAgent()) do cl
    wait(send_message(agent, "Message", address(cl[1][2])))
    wait(send_message(role, "Message", address(cl[1][2])))
    sleep(0.1)
end
```

Further, there are several specialized methods for sending messages, (1) [`send_tracked_message`](@ref), (2) [`send_and_handle_answer`](@ref), (3) [`reply_to`](@ref), (4) [`forward_to`](@ref).

(1) This function can be used to send a message with an automatically generated tracking id (uuid1) and it also accepts a response handler, which will
    automatically be called when a response arrives to the tracked message (care to include the tracking id when responding or just use [`reply_to`](@ref)).
(2) Variant of (1) which requires a response handler and enables the usage of the `do` syntax (see following code snippet).
(3) Convenience function to respond to a received message without the need to create the AgentAddress by yourself.
(4) Convenience function to forward messages to another agent. This function will set the approriate fields in the meta container to identify that a message has been forwarded and from which address it has been forwarded.

```@example
using Mango 

@agent struct MyMessageAgent end
@agent struct ReplyAgent end

agent1 = MyMessageAgent()
agent2 = PrintingAgent() # defined in Mango
agent3 = ReplyAgent()

function Mango.handle_message(agent::ReplyAgent, message::Any, meta::Any)
    # agent 3
    reply_to(agent, "Hello Agent, this is a response", meta) # (3)

    @info "Reply"
end
function handle_response(agent::MyMessageAgent, message::Any, meta::Any)
    # agent 1
    forward_to(agent, "Forwarded message", address(agent2), meta) # (4)

    @info "Handled response and forwarded the message" message
end

run_with_tcp(1, agent1, agent2, agent3) do cl
    wait(send_tracked_message(agent1, "Hello Agent, this is a tracked message", address(agent3); response_handler=handle_response)) # (1)
    wait(send_and_handle_answer(agent2, "Hello Agent, this is a different tracked message", address(agent3)) do agent, message, meta # (2)
        @info "Got an answer!"
    end)
    sleep(0.1)
end
```

There is also a possibility to enable automatic forwarding with adding so-called forwarding rules. For this you can use the function [`add_forwarding_rule`](@ref). To delete these rules the function [`delete_forwarding_rule`](@ref) exists.

## Task Scheduling

Agents can schedule tasks using the [`schedule`](@ref) function, which delegates to the [`Mango.schedule`](@ref) function. You can wait for all scheduled tasks to be completed using [`wait_for_all_tasks`](@ref). Here's how to schedule tasks:

```@example
using Mango

# Define your agent struct using @agent macro
@agent struct MyTaskAgent
    my_own_field::String
end
function my_task_function()
    @info "Task completed"
end

# Create an instance of the agent
my_agent = MyTaskAgent("MyValue")

# Schedule a task for the agent
wait(schedule(my_task_function, my_agent, InstantTaskData()))
```
