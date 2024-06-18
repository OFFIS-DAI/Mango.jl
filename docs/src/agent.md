# Agents

Agents are autonomous entities that can perceive their environment, make decisions, and interact with other agents and the system they inhabit. They are the building blocks of Mango.jl, representing the individual entities or actors within a larger system.


## 1. Agent Definition with @agent Macro

To define an agent the `@agent` macro can be used. It simplifies the process of defining an agent struct and automatically adds necessary baseline fields. Here's how you can define an agent:

```julia
using Mango

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end

# Create an instance of the agent
my_agent = MyAgent("MyValue")
```

The `@agent` macro adds the baseline fields listed in the table below. You can initialize the agent with exclusive fields like `my_own_field` in the example.

| Field        | Description                                                    | Usable?                                                                           |
|--------------|----------------------------------------------------------------|-----------------------------------------------------------------------------------|
| aid          | The id of the agent                                            | Yes with aid(agent)!                                                               |
| context      | Holds the reference to the container to send messages.         | Generally not recommended, use the convenience methods defined on the Agent type. |
| scheduler    | The scheduler of the agent                                     | Generally not recommended, use the convenience methods defined on the Agent type. |
| lock         | The agent lock to ensure only one message is handled per time. | Internal use only!                                                                |
| role_handler | Contains the roles and handles their interactions              | Internal use only!                                                                |


## 2. Role Management

Agents can have multiple roles associated with them. Roles can be added using the `add` function, allowing the agent to interact with its environment based on different roles. Here's how you can add roles to an agent:

```julia
using Mango

# Define your agent struct using @agent macro
@role struct MyRole
    my_own_field::String
end

# Assume you have already defined roles using Mango.AgentRole module
role1 = MyRole("Role1")
role2 = MyRole("Role2")

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end

# Create an instance of the agent
my_agent = MyAgent("MyValue")

# Add roles to the agent
add(my_agent, role1)
add(my_agent, role2)

# Now you can interact with the roles as needed
```

Additionally, roles can define the `setup` function to define actions to take when the roles are added to the agent. It is also possible to subscribe to specific messages using a boolean expression with the `subscribe(role::Role, handler::Function, condition::Function)` function. With the @role macro, the role context is added to the role, which contains the reference to the agent. However, it is recommended to use the equivalent methods defined on the role to execute actions like scheduling and sending messages.

## 3. Message Handling

Agents and Roles can handle incoming messages through the `handle_message` function. By default, it does nothing, but you can override it to define message-specific behavior. You can also add custom message handlers for specific roles using the `subscribe_handle` function. Here's how to handle messages:

```julia
using Mango

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end
@role struct MyRole
    my_own_field::String
end

# Override the default handle_message function for custom behavior
function handle_message(agent::MyAgent, message::Any, meta::Any)
    println("Received message @agent: ", message)
end
# Override the default handle_message function for custom behavior
function handle_message(role::MyRole, message::Any, meta::Any)
    println("Received message @role: ", message)
end
```

Besides the ability to handle messages, there also must be a possibility to send messages. This is implemented using the `send_message` function, defined on roles and agents.


```julia
using Mango

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end
@role struct MyRole
    my_own_field::String
end

agent = MyAgent("")
role = MyAgent("")

send_message(agent, "Message", AgentAddress("receiver_id", "receiver_addr", "optional tracking id"))
send_message(role, "Message", AgentAddress("receiver_id", "receiver_addr", "optional tracking id"))
```

Further, there are two specialized methods for sending methods, (1) `send_tracked_message` and (2) `reply_to`.

(1) This function can be used to send a message with an automatically generated tracking id (uuid1) and it also accepts a response handler, which will
    automatically be called when a response arrives to the tracked message (care to include the tracking id when responding or just use `reply_to`).
(2) Convenience function to respond to a received message without the need to create the AgentAddress by yourself.

```julia
agent1 = MyAgent("")
agent2 = MyAgent("")

function handle_message(agent::MyAgent, message::Any, meta::Any)
    # agent 2
    reply_to(agent, "Hello Agent, this is a response", meta) # (2)
end
function handle_response(agent::MyAgent, message::Any, meta::Any)
    # agent 1
end

send_tracked_message(agent1, "Hello Agent, this is a tracked message", AgentAddress(aid=agent2.aid); response_handler=handle_response) # (1)
```

## 4. Task Scheduling

Agents can schedule tasks using the `schedule` function, which delegates to the `Mango.schedule` function. You can wait for all scheduled tasks to be completed using `wait_for_all_tasks`. Here's how to schedule tasks:

```julia
using Mango

# Define your agent struct using @agent macro
@agent struct MyAgent
    my_own_field::String
end

# Create an instance of the agent
my_agent = MyAgent("MyValue")

# Schedule a task for the agent
schedule(my_task_function, my_agent, PeriodicTaskData(5.0)) # Schedule a task to run every 5 seconds

# Wait for all scheduled tasks to complete
wait_for_all_tasks(my_agent)
```
