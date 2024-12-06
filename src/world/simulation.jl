export World, register, send_message, shutdown, protocol_addr,
    create_world, step_simulation, SimulationResult, CommunicationSimulationResult,
    TaskSimulationResult, on_step, discrete_step_until, env, space, time, clock

using Base.Threads
using Dates
using ConcurrentCollections
using OrderedCollections

""" 
Id key for the receiver in the meta dict
"""
RECEIVER_ID::String = "receiver_id"
""" 
Prefix for the generated aid's 
"""
AGENT_PREFIX::String = "agent"
""" 
DISCRETE EVENT STEP SIZE
"""
DISCRETE_EVENT::Real = -1

"""
    create_world(start_time::DateTime; communication_sim::Union{Nothing,CommunicationSimulation}=nothing, task_sim::Union{Nothing,TaskSimulation}=nothing)

Create a simulation world. The world is intitialized with `start_time`. 

Per default the [`SimpleCommunicationSimulation`](@ref) is used for communication simulation, and
[`SimpleTaskSimulation`](@ref) for simulating the tasks of agents. To replace these, `communication_sim`
and respectively `task_sim` can be set.
"""
function create_world(start_time::DateTime;
    communication_sim::Union{Nothing,CommunicationSimulation}=nothing,
    task_sim::Union{Nothing,TaskSimulation}=nothing,
    space::Union{Nothing,Space}=nothing,
    behavior::Union{Nothing,Behavior}=nothing)

    world = World()
    world.clock.simulation_time = start_time
    if !isnothing(communication_sim)
        world.communication_sim = communication_sim
    end
    if !isnothing(task_sim)
        world.task_sim = task_sim
    end
    if !isnothing(space)
        world.env.space = space
    end
    if !isnothing(behavior)
        world.env.behavior = behavior
    end
    add_observer!(world.env, world.world_observer)
    add_simulation_scheduler!(world.task_sim, world.env.scheduler)
    return world
end

"""
Represents a message data package including the arriving time of the package.
"""
struct MessageData
    content::Any
    meta::AbstractDict
    arriving_time::DateTime
end

struct DispatchToAgentWorldObserver <: WorldObserver
    agents_ref::OrderedDict{String,Agent}
end

function dispatch_global_event(observer::DispatchToAgentWorldObserver, event::Any)
    for agent in values(observer.agents_ref)
        dispatch_global_event(agent, event)
    end
end

"""
The World used as a base struct to enable simulations in Mango.jl. Always create using [`create_world`](@ref).
"""
@kwdef mutable struct World <: ContainerInterface
    clock::Clock = Clock(DateTime(0))
    env::Environment = Environment(scheduler=SimulationScheduler(clock=clock))
    task_sim::TaskSimulation = SimpleTaskSimulation(clock=clock)
    agents::OrderedDict{String,Agent} = OrderedDict{String,Agent}()
    agent_counter::Integer = 0
    shutdown::Bool = false
    communication_sim::CommunicationSimulation = SimpleCommunicationSimulation()
    message_queue::ConcurrentQueue{MessageData} = ConcurrentQueue{MessageData}()
    world_observer::WorldObserver = DispatchToAgentWorldObserver(agents)
end

function agents(world::World)::Vector{Agent}
    return [t[2] for t in collect(world.agents)]
end

"""
    on_step(agent::Agent, env::Environment, clock::Clock, step_size_s::Real)

Hook-in, called on every step of the simulation world for every `agent`.

Further, the `world` is passed, which represents a common view on the environment
in which agents can interact with eachother. Besides, the `clock` and the `step_size_s`
can be used to read the current simulation time and the time which passes in the current step.
"""
function on_step(agent::Agent, env::Environment, clock::Clock, step_size_s::Real)
    # default nothing
end

function on_step(role::Role, env::Environment, clock::Clock, step_size_s::Real)
    # default nothing
end

"""
Internal, call on_step on all agents.
"""
function step_agent(agent::Agent, env::Environment, clock::Clock, step_size_s::Real)
    on_step(agent, env, clock, step_size_s)
    for role in roles(agent)
        on_step(role, env, clock, step_size_s)
    end
end

"""
Contains the result of the communication simulation and whether the state of
the world has changed
"""
struct MessagingIterationResult
    communication_result::CommunicationSimulationResult
    state_changed::Bool
end

"""
Result of all messaging simulation iterations.
"""
@kwdef struct MessagingSimulationResult
    results::Vector{MessagingIterationResult} = Vector()
end

"""
Result of all task simulation iterations.
"""
@kwdef struct TaskSimulationResult
    results::Vector{TaskIterationResult} = Vector()
end

"""
Result of one simulation step.
"""
struct SimulationResult
    time_elapsed::Real
    messaging_result::MessagingSimulationResult
    task_result::TaskSimulationResult
    simulation_step_size_s::Real
end

"""
Internal
"""
function to_message_package(message_data::MessageData)::MessagePackage
    sender_aid = message_data.meta[SENDER_ID]
    receiver_aid = message_data.meta[RECEIVER_ID]
    return MessagePackage(sender_aid, receiver_aid, message_data.arriving_time, (message_data.content, message_data.meta))
end

"""
Internal
"""
function to_cs_input!(message_queue::ConcurrentQueue{MessageData})::Vector{MessagePackage}
    messages_packages = Vector()
    while true
        some_message = maybepopfirst!(message_queue)
        if isnothing(some_message)
            break
        end
        message::MessageData = something(some_message)
        push!(messages_packages, to_message_package(message))
    end
    return messages_packages
end

"""
Internal
"""
function to_cs_input(message_queue::ConcurrentQueue{MessageData})::Vector{MessagePackage}
    messages_packages = Vector()
    next = message_queue.head.next
    while !isnothing(next)
        message::MessageData = next.value
        push!(messages_packages, to_message_package(message))
        next = next.next
    end
    return messages_packages
end

"""
Internal
"""
function cs_step_iteration(world::World,
    step_size_s::Real,
    pre_communication_result::Union{Nothing,CommunicationSimulationResult})::MessagingIterationResult
    message_packages = to_cs_input!(world.message_queue)
    communication_result = pre_communication_result
    if isnothing(communication_result)
        communication_result = calculate_communication(world.communication_sim,
            clock(world),
            message_packages)
    end
    state_changed = false
    @sync begin
        for (mp, pr) in sort([z for z in zip(message_packages, communication_result.package_results)], by=t -> add_seconds(t[1].sent_date, t[2].delay_s))
            if add_seconds(mp.sent_date, pr.delay_s) <= add_seconds(time(world), step_size_s) && pr.reached
                state_changed = true
                @spawnlog process_message(world, mp.content[1], mp.content[2])
            else
                # process it later
                push!(world.message_queue, MessageData(mp.content[1], mp.content[2], mp.sent_date))
            end
        end
    end
    return MessagingIterationResult(communication_result, state_changed)
end

"""
Internal
"""
function determine_time_step(world::World)
    message_packages = to_cs_input(world.message_queue)
    communication_result = calculate_communication(world.communication_sim, clock(world), message_packages)

    # earliest message or -1 if no message arrives
    message_arrival_times = [add_seconds(t[1].sent_date, t[2].delay_s) for t in zip(message_packages, communication_result.package_results)]
    time_to_next_message_s = nothing
    if length(message_arrival_times) > 0
        time_to_next_message_s = (findmin(message_arrival_times)[1] - time(world)).value / 1000
    end
    @debug "Next message in $time_to_next_message_s"

    # ealiest task or -1 if no task scheduled
    next_event_s = determine_next_event_time(world.task_sim)

    @debug "Next event in $next_event_s"

    # check whether one is absent and the other is present
    if isnothing(time_to_next_message_s) && isnothing(next_event_s)
        return nothing, communication_result
    elseif isnothing(next_event_s)
        return time_to_next_message_s, communication_result
    elseif isnothing(time_to_next_message_s)
        return next_event_s, communication_result
    end

    # return earliest
    return min(time_to_next_message_s, next_event_s), communication_result
end

"""
    step_simulation(world::World, step_size_s::Real=DISCRETE_EVENT)::Union{SimulationResult,Nothing}

Step the simulation using a continous time-span or until the next event happens. 

For the continous simulation a `step_size_s` can be freely chosen, for the discrete event type 
DISCRETE_EVENT has to be set for the `step_size_s`.
"""
function step_simulation(world::World, step_size_s::Real=DISCRETE_EVENT)::Union{SimulationResult,Nothing}
    # Init world if uninitialized
    if !initialized(world.env)
        initialize(world.env, [v for v in values(world.agents)])
    end

    state_changed = true

    @debug "Time at the start of the step" time(world)

    task_sim_result = TaskSimulationResult()
    messaging_sim_result = MessagingSimulationResult()
    first_step = true
    time_step_s = step_size_s

    # We are in discrete event mode, so we need to determine
    # the time until the next event occurs, this time will
    # be used to execute the time-based simulation
    comm_result = nothing
    if time_step_s == DISCRETE_EVENT
        time_step_s, comm_result = determine_time_step(world)
        @debug "Determined the size to be $time_step_s"
        if isnothing(time_step_s)
            return nothing
        end
    end
    elapsed = @elapsed begin
        # now we process everything which happened in the steps,
        # tasks and previous iterations
        while state_changed
            @debug "Start simulation iteration"
            task_iter_result = nothing
            comm_iter_result = nothing
            @sync begin
                Threads.@spawn comm_iter_result = cs_step_iteration(world, time_step_s, first_step ? comm_result : nothing)
                Threads.@spawn task_iter_result = step_iteration(world.task_sim, time_step_s, first_step)
            end
            first_step = false
            push!(task_sim_result.results, task_iter_result)
            push!(messaging_sim_result.results, comm_iter_result)
            state_changed = comm_iter_result.state_changed || task_iter_result.state_changed
            @debug "Finish simulation iteration" state_changed
        end

        step(world.env, clock(world), time_step_s)

        # agents act on the stepping hook
        for agent in values(world.agents)
            step_agent(agent, world.env, clock(world), time_step_s)
        end
    end
    @debug "The simulation step needed $elapsed seconds"

    world.clock.simulation_time = add_seconds(time(world), time_step_s)

    @debug "New time" time(world)

    return SimulationResult(elapsed, messaging_sim_result, task_sim_result, time_step_s)
end

"""
    discrete_event_simulation(world::World, max_advance_time_s::Real)

Execute a discrete event simulation using the `world` with the maximal allowed advanced time
of the simulation of `max_advance_time_s`. 

This function will step the world until the clock has advanced to the initial_time + `max_advance_time_s`
or if the time of the world does not advance anymore (which would mean no events are scheduled).
"""
function discrete_step_until(world::World, max_advance_time_s::Real)
    initial_time = time(world)
    prev_time = nothing
    results = []

    while isnothing(prev_time) || ((prev_time < time(world) || length(results) == 1)
                                   &&
                                   initial_time + Second(max_advance_time_s) > time(world))

        prev_time = time(world)
        push!(results, step_simulation(world))
    end
    return results
end

function protocol_addr(world::World)
    return nothing
end

function shutdown(world::World)
    world.shutdown = true

    for agent in values(world.agents)
        shutdown(agent)
    end
end

function register(
    world::World,
    agent::Agent,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
)
    actual_aid::String = "$AGENT_PREFIX$(world.agent_counter)"
    if !isnothing(suggested_aid) && !haskey(world.agents, suggested_aid)
        actual_aid = suggested_aid
    end
    world.agents[actual_aid] = agent
    agent.aid = actual_aid
    agent.context = AgentContext(world)
    world.agent_counter += 1

    if !isnothing(world.task_sim)
        agent.scheduler = create_agent_scheduler(world.task_sim)
    end

    return agent
end

function process_message(world::World, msg::Any, meta::AbstractDict)
    receiver_id = meta[RECEIVER_ID]

    if !haskey(world.agents, meta[RECEIVER_ID])
        @warn "Container $(keys(world.agents)) has no agent with id: $receiver_id" msg meta
    else
        agent = world.agents[receiver_id]
        return dispatch_message(agent, msg, meta)
    end
end

struct NonWaitable end
function Base.wait(waitable::NonWaitable) end

function forward_message(world::World, msg::Any, meta::AbstractDict)
    push!(world.message_queue, MessageData(msg, meta, time(world)))
    return NonWaitable()
end

function send_message(
    world::World,
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

    return forward_message(world, content, meta)
end

"""
    Base.getindex(world::World, index::String)

Return the agent indexed by `index` (aid). 
"""
function Base.getindex(world::World, index::String)
    return world.agents[index]
end
function Base.getindex(world::World, index::Int)
    return agents(world)[index]
end

function env(world::World)
    return env(world.env)
end

function space(world::World)
    return space(world.env)
end

function clock(world::World)
    return world.clock
end

function time(world::World)
    return clock(world).simulation_time
end