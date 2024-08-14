
export ContainerInterface, send_message, protocol_addr, Address, AgentAddress, MQTTAddress, SENDER_ADDR, SENDER_ID, TRACKING_ID, run_mango

# id key for the sender address
SENDER_ADDR::String = "sender_addr"
# id key for the sender 
SENDER_ID::String = "sender_id"
# id key for the tracking number used for dialogs
TRACKING_ID::String = "tracking_id"

"""
Supertype of every container implementation. This acts as an interface to be used by the agents
in their contexts.
"""
abstract type ContainerInterface end

"""
Supertype of all address types
"""
abstract type Address end

"""
Default AgentAddress base type, where the agent identifier is based on the container created agent id (aid).
Used with the TCP protocol.
"""
@kwdef struct AgentAddress <: Address
    aid::Union{String,Nothing}
    address::Any = nothing
    tracking_id::Union{String,Nothing} = nothing
end

"""
Connection information for an MQTT topic on a given broker. 
Used with the MQTT protocol. 
"""
@kwdef struct MQTTAddress <: Address
    broker::Any = nothing
    topic::String
end

"""
Send a message `message using the given container `container`
to the given address. Additionally, further keyword
arguments can be defines to fill the internal meta data of the message.

This only defines the function API, the actual implementation is done in the core container
module.
"""
function send_message(
    container::ContainerInterface,
    content::Any,
    address::Address,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...
)
    @warn "The API send_message definition has been called, this should never happen. There is most likely an import error."
end

"""
Used by the agent to get the protocol addr part
"""
function protocol_addr(container::ContainerInterface) end

function start(container::ContainerInterface) end
function shutdown(container::ContainerInterface) end

"""
    run_mango(runnable, container_list)

Run a Mango.jl agent system using the container included in `container_list` and therefor,
the agents included in these containers. The runnable defines what the agent system shall
do. In most cases the runnable will execute code, which starts some process (e.g. some
distributed negotiation) in the system.

Generally this function is a convenience function and is equivalent to starting all containers 
in the list, executing the code represented by `runnable` and shuting down the container again.

# Examples
```julia
run_mango(your_containers) do 
   # Send the first message to start the system
   send_message(defined_agent, "Starting somethin", address(other_defined_agent))

   # wait some time
   wait(some_stopping_condition)
end
```
"""
function run_mango(runnable_simulation_code::Function, container_list::Vector{T}) where T <: ContainerInterface
    
    for container in container_list
        wait(Threads.@spawn start(container))
    end

    runnable_simulation_code()

    @sync begin
        for container in container_list
            Threads.@spawn shutdown(container)
        end
    end
end

function run_mango(runnable_simulation_code::Function, container::ContainerInterface)
    run_mango(runnable_simulation_code, [container])
end
