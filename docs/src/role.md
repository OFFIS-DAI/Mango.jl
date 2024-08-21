# Roles

Roles are used to provide a mechanism for reusability and modularization of functionsalities provided/implemented by agents. Every agent can contain and unlimited number of roles, which are separate structs on which typical agent functionalitites (like send_message) can be defined. All roles of an agent share the same address and agent id, as they are part of the agent and no autonomous unit for themself. 

## Role definition

A role can be defined using the [`@role`](@ref) macro. This macro adds some baselinefields to the following struct definition. The struct can be defined like any other Julia struct.

```julia
# Define your role struct using @role macro
@role struct MyRole
    my_own_field::String
end

# Assume you have already defined roles using Mango.AgentRole module
role1 = MyRole("Role1")
```

Most functions, used for agent development can also be used with roles (e.g. [`handle_message`](@ref), [`address`](@ref), [`schedule`](@ref), [`send_message`](@ref) (plus variants) and the lifecycle methods).  

Additionally, roles can define the [`setup`](@ref) function to define actions to take when the roles are added to the agent. It is also possible to subscribe to specific messages using a boolean expression with the [`subscribe_message`](@ref) function. With the @role macro, the role context is added to the role, which contains the reference to the agent. However, it is recommended to use the equivalent methods defined on the role to execute actions like scheduling and sending messages. Further with roles it is possible to listen to all messages sent from within the agent. For this [`subscribe_send`](@ref) can be used.

## Role communication

Besides the message subscriptions there are functionalities to communicate/work together with other roles. There are two different mechanisms for this:
* Data sharing
* An event system

### Data sharing

The data sharing can be used using ordinary Julia structs with default constructors. There are two ways to share the data, first you can create the model you want share with
[`get_model`](@ref)

```julia
struct TestModel
    c::Int64
end
TestModel() = TestModel(42)
role = MyRole("Role1")
shared_model = get_model(role, TestModel)
```

Mango.jl will create a TestModel instance and manage this instance such that every role can access it. 

Although this is a straightforward method it can be very clumsy to use. For this reason there is the macro [`@shared`](@ref), which can be used within a role definition
to mark a field as shared model. Then, Mango.jl will ensure that a shared instance of the declared type will be created and assigned to the struct field.

```julia
@role struct SharedFieldTestRole
    @shared 
    test_model::TestModel
end
```


### Event system


Roles can emit events using [`emit_event`](@ref). If `event_type` is nothing, the type of `event` will be used as `event_type`. To handle these events roles can subscribe using [`subscribe_event`](@ref) or add a method to [`handle_event`](@ref).

```julia

struct TestEvent
end

function handle_event(role::Role, src::Role, event::TestEvent; event_type::Any)
    @info "Event is arriving!"
end
function custom_handler(role::Role, src::Role, event::Any, event_type::Any)
    @info "Event is also arriving!"
end

@agent struct RoleTestAgent
    counter::Integer
end

agent = RoleTestAgent(0)

role_emitter = MyRole("Role1")
role_handler = MyRole("Role1")

add(agent, role_emitter)
add(agent, role_handler)    
subscribe_event(role1, TestEvent, custom_handler, (src, event) -> true) # condition is optional

emit_event(role_emitter, TestEvent())
```