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

The `@agent` macro adds baseline fields such as `lock`, `context`, `role_handler`, `scheduler`, and `aid`. You can initialize the agent with exclusive fields like `my_own_field` in the example.

## 1. Role Management

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

Additionally, roles can define the `setup` function to define actions to take when the roles are added to the agent. It is also possible to subscribe to specific messages using a boolean expression with the `subscribe(role::Role, handler::Function, condition::Function)` function.

## 1. Message Handling

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
function handle_message(agent::MyRole, message::Any, meta::Any)
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

send_message(agent, "Message", "receiver_id", "receiver_addr")
send_message(role, "Message", "receiver_id", "receiver_addr")
```


## 1. Task Scheduling

Agents can schedule tasks using the `schedule` function, which delegates to the `Mango.schedule` function. You can wait for all scheduled tasks to complete using `wait_for_all_tasks`. Here's how to schedule tasks:

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