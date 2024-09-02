export create_tcp_container, create_mqtt_container, GeneralAgent, add_agent_composed_of, agent_composed_of, activate, run_in_real_time, run_in_simulation, run_with_mqtt, run_with_tcp

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
    agent_composed_of(roles::Role...)

Create an agent which is composed of the given roles `roles...`.

The agent struct used is an empty struct, it is only used as a container
for the roles. The created agent will be returned by the function.

# Examples
```julia
agent = agent_composed_of(RoleA(), RoleB(), RoleC())
```
"""
function agent_composed_of(roles::Role...)
    agent = GeneralAgent()
    for role in roles
        add(agent, role)
    end
    return agent
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
    agent = agent_composed_of(roles...)
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

"""
    run_in_real_time(runnable::Function,
    n_container::Int,
    container_list_creator::Function,
    agents::Union{Tuple,Agent}...)

Let the agents run in containers (real time).

Distributes the given `agents` to `n_container` (real time container) and execute the `runnable` 
(takes the container list as argument) while the container are active to run. It is possible to 
add supplementary information per agent as Tuple. For example `(Agent, :aid => "my_aid")`.
The type of the containers are determined by the `container_list_creator` (n_container as argument, has
to return a list of container with n_container entries).
"""
function run_in_real_time(runnable::Function,
    n_container::Int,
    container_list_creator::Function,
    agents::Union{Tuple,Agent}...)

    actual_number_container = n_container
    if n_container < length(agents)
        actual_number_container = length(agents)
    end
    container_list = container_list_creator(actual_number_container)
    for (i, agent) in enumerate(agents)
        container_id = ((i - 1) % actual_number_container) + 1
        if isa(agent, Tuple)
            actual_agent = agent[1]
            agent_params::Dict = Dict(agent[2])
            register(container_list[container_id], actual_agent, get(agent_params, :aid, nothing),
                topics=get(agent_params, :topics, []))
        else
            register(container_list[container_id], agent)
        end
    end
    activate(container_list) do
        runnable(container_list)
    end
end

"""
    run_with_tcp(runnable::Function,
    n_container::Int,
    agents::Union{Tuple,Agent}...;
    host::String="127.0.0.1",
    start_port::Int=5555,
    codec::Union{Nothing,Tuple{Function,Function}}=(encode, decode))

Let the agents run in tcp containers (real time).

Distributes the given `agents` to `n_container` (real time container) and execute the `runnable` 
(takes the container list as argument) while the container are active to run.
Here, TCP container are created on `host` starting with the port `start_port`.
"""
function run_with_tcp(runnable::Function,
    n_container::Int,
    agents::Union{Tuple,Agent}...;
    host::String="127.0.0.1",
    start_port::Int=5555,
    codec::Union{Nothing,Tuple{Function,Function}}=(encode, decode))
    run_in_real_time(runnable, n_container, n -> [create_tcp_container(host, start_port + (i - 1), codec=codec) for i in 1:n], agents...)
end

"""
    run_with_mqtt(runnable::Function,
    n_container::Int,
    agents::Union{Tuple,Agent}...;
    broker_host::String="127.0.0.1",
    broker_port::Int=1883,
    codec::Union{Nothing,Tuple{Function,Function}}=(encode, decode))
 
Let the agents run in mqtt containers (real time).

Distributes the given `agents` to `n_container` (real time container) and execute the `runnable` 
(takes the container list as argument) while the container are active to run.
Here, MQTT container are created with the broker on `broker_host` and at the port `broker_port`.
The containers are assignede client ids (client1 client2 ...)  
"""
function run_with_mqtt(runnable::Function,
    n_container::Int,
    agents::Union{Tuple,Agent}...;
    broker_host::String="127.0.0.1",
    broker_port::Int=1883,
    codec::Union{Nothing,Tuple{Function,Function}}=(encode, decode))
    run_in_real_time(runnable, n_container, n -> [create_mqtt_container(broker_host, broker_port, "client" * string(i), codec=codec) for i in 1:n], agents...)
end

"""
    run_in_simulation(runnable::Function, agents::Agent, n_steps::Int; start_time::DateTime=DateTime(2000, 1, 1), step_size_s::Int=DISCRETE_EVENT)

Let the agents run as simulation in a simulation container.

Execute the `runnable` in [`SimulationContainer`](@ref) while the container is active to run. After the
runnable the simulation container is stepped `n_steps` time with a `step_size_s` (default is discrete event).
The start time can be specified using `start_time`.
"""
function run_in_simulation(runnable::Function, n_steps::Int, agents::Agent...; start_time::DateTime=DateTime(2000, 1, 1), step_size_s::Int=DISCRETE_EVENT)
    sim_container = create_simulation_container(start_time)
    for agent in agents
        register(sim_container, agent)
    end
    activate(sim_container) do
        runnable(sim_container)
        for _ in 1:n_steps
            step_simulation(sim_container, step_size_s)
        end
    end
end