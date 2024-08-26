export create_tcp_container, create_mqtt_container, GeneralAgent, add_agent_composed_of, activate

function _set_codec(container::Container, codec::Union{Nothing,Tuple{Function,Function}})
    if !isnothing(codec)
        container.codec = codec
    end
end

"""
	create_tcp_container(host, port; codec=nothing)

Create a container using an TCP protocol. 

The `host` is expected to be the IP-adress to bind on, `port` is the port to bind on. Optionally you 
can also provide a codec as tuple of functions (first encode, second decode, see 
[`encode`](@ref) and [`decode`](@ref)).

# Examples
```julia
agent = create_mqtt_container("127.0.0.1", 5555, "MyClient")
```
"""
function create_tcp_container(host::String, port::Int; codec::Union{Nothing,Tuple{Function,Function}}=nothing)
    container = Container()
    container.protocol = TCPProtocol(address=InetAddr(host, port))
    _set_codec(container, codec)
    return container
end

"""
	create_mqtt_container(host, port, client_id; codec=nothing)

Create a container using an MQTT protocol. 

The `host` is expected to be the IP-adress of the broker, `port` is the port of the broker, 
the `client_id` is the id of the client which will be created and connected to the broker. 
Optionally you can also provide a codec as tuple of functions (first encode, second decode, see 
[`encode`](@ref) and [`decode`](@ref)).

# Examples
```julia
agent = create_mqtt_container("127.0.0.1", 5555, "MyClient")
```
"""
function create_mqtt_container(host::String, port::Int, client_id::String; codec::Union{Nothing,Tuple{Function,Function}}=nothing)
    container = Container()
    container.protocol = MQTTProtocol(client_id, InetAddr(host, port))
    _set_codec(container, codec)
    return container
end

@agent struct GeneralAgent
end

"""
	add_agent_composed_of(container, roles...)

Create an agent which is composed of the given roles `roles...` and register the agent 
to the `container`. 

The agent struct used is an empty struct, it is only used as a container
for the roles. The created agent will be returned by the function.

# Examples
```julia
agent = add_agent_composed_of(your_container, RoleA(), RoleB(), RoleC())
```
"""
function add_agent_composed_of(container::ContainerInterface, roles::Role...; suggested_aid::Union{Nothing,String}=nothing)
    agent = GeneralAgent()
    for role in roles
        add(agent, role)
    end
    register(container, agent, suggested_aid)
    return agent
end

"""
	activate(runnable, container_list)

Actvate the container(s), which includes starting the containers and shutting them down
after the runnable has been executed. 

In most cases the runnable will execute code, which starts some process 
(e.g. some distributed negotiation) in the system to define the objective of the agent system.

Generally this function is a convenience function and is equivalent to starting all containers 
in the list, executing the code represented by `runnable` and shuting down the container again.
Further, this function will handle errors occuring while running the `runnable` and ensure the
containers are shutting down.

# Examples
```julia
activate(your_containers) do 
   # Send the first message to start the system
   send_message(defined_agent, "Starting somethin", address(other_defined_agent))

   # wait some time
   wait(some_stopping_condition)
end
```
"""
function activate(runnable_simulation_code::Function, container_list::Vector{T}) where {T<:ContainerInterface}

    @sync begin
        for container in container_list
            Threads.@spawn start(container)
        end
    end
    for container in container_list
        notify_ready(container)
    end
    try
        runnable_simulation_code()
    catch e
        @error "A nested error ocurred while running a mango simulation" exception = (e, catch_backtrace())
    finally
        @sync begin
            for container in container_list
                Threads.@spawn shutdown(container)
            end
        end
    end
end

function activate(runnable_simulation_code::Function, container::ContainerInterface)
    activate(runnable_simulation_code, [container])
end
