

"""
Represents a message data package including the arriving time of the package.
"""
struct MessageData
    content::Any
    meta::AbstractDict
    arriving_time::DateTime
end

@kwdef mutable struct SimulationContainer <: ContainerInterface
    clock::Clock
    agents::OrderedDict{String,Agent} = OrderedDict{String,Agent}()
    agent_counter::Integer = 0
    shutdown::Bool = false
    message_queue::ConcurrentQueue{MessageData} = ConcurrentQueue{MessageData}()
end

function agents(container::SimulationContainer)::Vector{Agent}
    return [t[2] for t in collect(container.agents)]
end

function messages(container::SimulationContainer)::ConcurrentQueue{MessageData}
    return container.message_queue
end

function register(
    container::SimulationContainer,
    agent::Agent,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
)
    actual_aid::String = "$AGENT_PREFIX$(container.agent_counter)"
    if !isnothing(suggested_aid) && !haskey(container.agents, suggested_aid)
        actual_aid = suggested_aid
    end
    container.agents[actual_aid] = agent
    agent.aid = actual_aid
    agent.context = AgentContext(container)
    container.agent_counter += 1

    return agent
end

function forward_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
    push!(container.message_queue, MessageData(msg, meta, time(container)))
    return NonWaitable()
end

function send_message(
    container::SimulationContainer,
    content::Any,
    agent_adress::AgentAddress,
    sender_id::Union{Nothing,String}=nothing;
    kwargs...,
)
    receiver_id = agent_adress.aid
    tracking_id = agent_adress.tracking_id

    meta = OrderedDict{String,Any}()
    for (key, value) in kwargs
        meta[string(key)] = value
    end

    meta[RECEIVER_ID] = receiver_id
    meta[SENDER_ID] = sender_id
    meta[TRACKING_ID] = tracking_id
    meta[SENDER_ADDR] = nothing

    @debug "Send a message to ($receiver_id), from $sender_id" typeof(content)

    return forward_message(container, content, meta)
end


function process_message(container::SimulationContainer, msg::Any, meta::AbstractDict)
    receiver_id = meta[RECEIVER_ID]

    if !haskey(container.agents, meta[RECEIVER_ID])
        @warn "Container $(keys(container.agents)) has no agent with id: $receiver_id" msg meta
    else
        agent = container.agents[receiver_id]
        return dispatch_message(agent, msg, meta)
    end
end

"""
    Base.getindex(container::SimulationContainer, index::String)

Return the agent indexed by `index` (aid). 
"""
function Base.getindex(container::SimulationContainer, index::String)
    return container.agents[index]
end
function Base.getindex(container::SimulationContainer, index::Int)
    return agents(container)[index]
end

function shutdown(container::SimulationContainer)
    container.shutdown = true

    for agent in agents(container)
        shutdown(agent)
    end
end

function protocol_addr(container::SimulationContainer)
    return nothing
end

function clock(container::SimulationContainer)
    return container.clock
end

function time(container::SimulationContainer)
    return clock(container).simulation_time
end