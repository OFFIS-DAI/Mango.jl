export World, register, send_message, shutdown, protocol_addr,
    create_world, step_simulation, SimulationResult, CommunicationSimulationResult,
    TaskSimulationResult, on_step, discrete_step_until, env, space, time, clock,
    record_world!, record_agent!, record_agent_having!, record_position!, position_history,
    MessageTransaction, data_collection, data_agent_collection,
    agent_recording_as_plottable, agent_recordings_as_dict

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

    world = World(clock=Clock(start_time))
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

struct DispatchToAgentWorldObserver <: WorldObserver
    agents_ref::OrderedDict{String,Agent}
end

function dispatch_global_event(observer::DispatchToAgentWorldObserver, clock::Clock, event::Any)
    for agent in values(observer.agents_ref)
        dispatch_global_event(agent, clock, event)
    end
end

"""
A WorldRecording is a container to record data in the world.
"""
@kwdef mutable struct WorldRecording
    timeseries::Vector{Any} = Vector()
    time::Vector{Real} = Vector()
    data::Any = nothing
    no_plot = false
end

"""
An AgentsRecording is a container to record data of the agents.
"""
@kwdef mutable struct AgentsRecording
    timeseries::Dict{String,Vector{Any}} = Dict()
    time::Vector{Real} = Vector()
    data::Any = nothing
    dedicated_plots = false
    no_plot = false
end

function get_x(agents_recording::AgentsRecording)
    return agents_recording.time
end

function get_labels_and_ys(agents_recording::AgentsRecording)
    pairs = collect(agents_recording.timeseries)
    labels = first.(pairs)
    ys_last = last.(pairs)
    ys = nothing
    if length(ys_last) == 1
        ys = Float64.(ys_last[1]) 
    else 
        ys = Float64.(hcat(ys_last...)) 
    end
    return labels, ys
end

struct MessageTransaction
    sender_id::Union{String,Nothing}
    receiver_id::String
    sent_date::DateTime
    arriving_date::DateTime
    content::Any
end

"""
The World used as a base struct to enable simulations in Mango.jl. Always create using [`create_world`](@ref).
"""
@kwdef mutable struct World <: ContainerInterface
    clock::Clock = Clock(DateTime(0))
    env::Environment = DefaultEnvironment(scheduler=SimulationScheduler(clock=clock))
    container::SimulationContainer = SimulationContainer(clock=clock, env=env)
    task_sim::TaskSimulation = SimpleTaskSimulation(clock=clock)
    communication_sim::CommunicationSimulation = SimpleCommunicationSimulation()
    world_observer::WorldObserver = DispatchToAgentWorldObserver(container.agents)
    data_collections::OrderedDict{String,WorldRecording} = OrderedDict()
    data_agent_collections::OrderedDict{String,AgentsRecording} = OrderedDict()
    data_collectors::Vector{Function} = Vector()
    recorded_messages::Vector{MessageTransaction} = Vector()
end

function agents(world::World)::Vector{Agent}
    return agents(world.container)
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
    return MessagePackage(sender_aid, receiver_aid, message_data.arrival_time, (message_data.content, message_data.meta))
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
    message_packages = to_cs_input!(messages(world.container))
    communication_result = pre_communication_result
    if isnothing(communication_result) || length(message_packages) != length(communication_result.package_results)
        communication_result = calculate_communication(world.communication_sim,
            clock(world),
            message_packages)
    end
    state_changed = false
    @sync begin
        for (mp, pr) in sort([z for z in zip(message_packages, communication_result.package_results)], by=t -> add_seconds(t[1].sent_date, t[2].delay_s))
            if !pr.reached
                continue
            end
            if add_seconds(mp.sent_date, pr.delay_s) <= add_seconds(time(world), step_size_s)
                state_changed = true
                push!(world.recorded_messages, MessageTransaction(mp.sender_id,
                    mp.receiver_id,
                    mp.sent_date,
                    add_seconds(mp.sent_date, pr.delay_s),
                    mp.content[1]))
                Threads.@spawn try
                    process_message(world.container, mp.content[1], mp.content[2])
                catch ex
                    log_exception(ex)
                    rethrow(ex)
                end
            else
                # process it later
                push!(messages(world.container), MessageData(mp.content[1], mp.content[2], mp.sent_date))
            end
        end
    end
    return MessagingIterationResult(communication_result, state_changed)
end

"""
Internal
"""
function determine_time_step(world::World)
    message_packages = to_cs_input(messages(world.container))
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
    record!(recording::WorldRecording, time::Real, data::Any)

Record data `data` at time `time` in the `recording`.
"""
function insert_world_recording!(recording::WorldRecording, world::World, data::Any)
    push!(recording.time, seconds_elapsed(clock(world)))
    push!(recording.timeseries, data)
end

function insert_agent_recording!(recording::AgentsRecording, world::World, agent::Agent, data::Any)
    timeseries = get!(recording.timeseries, aid(agent), Vector())
    push!(timeseries, data)
end

function do_recordings(world::World)
    for collector in world.data_collectors
        collector(world)
    end
end

function step_all_entities(world::World, time_step_s::Real)

    # Stepping of the hook-based entities always happens
    step(world.env, clock(world), time_step_s)
    # agents act on the stepping hook
    for agent in values(agents(world))
        step_agent(agent, world.env, clock(world), time_step_s)
    end
end

elapsed_det::Real = 0
elapsed_step::Real = 0
elapsed_sim::Real = 0
elapsed_rec::Real = 0

"""
    step_simulation(world::World, step_size_s::Real=DISCRETE_EVENT; max_advance_time_s::Real=-1)::Union{SimulationResult,Nothing}

Step the simulation using a continous time-span or until the next event happens. 

For the continous simulation a `step_size_s` can be freely chosen, for the discrete event type 
DISCRETE_EVENT has to be set for the `step_size_s`. If you choose DISCRETE_EVENT, you can also specify 
a max_advance_time_s, which will abort the step if the determined step_size exceeds the max_advance_time_s.
"""
function step_simulation(world::World, step_size_s::Real=DISCRETE_EVENT; max_advance_time_s::Real=-1)::Union{SimulationResult,Nothing}
    # Init world if uninitialized
    if !initialized(world.env)
        initialize(world.env, [v for v in values(agents(world))], world.clock)
        do_recordings(world)
    end

    state_changed = true

    @debug "Time at the start of the step" time(world)

    task_sim_result = TaskSimulationResult()
    messaging_sim_result = MessagingSimulationResult()
    first_step = true
    time_step_s = step_size_s

    elapsed = @elapsed begin
        # We are in discrete event mode, so we need to determine
        # the time until the next event occurs, this time will
        # be used to execute the time-based simulation
        comm_result = nothing
        if time_step_s == DISCRETE_EVENT
            time_step_s, comm_result = determine_time_step(world)
            @debug "Determined the size to be $time_step_s"
            if isnothing(time_step_s) || (max_advance_time_s != -1 && time_step_s > max_advance_time_s)
                # only step guaranteed entities
                step_all_entities(world, 0)
                return nothing
            end
        end
        world.container.step_size_s = time_step_s
    end

    global elapsed_det
    elapsed_det += elapsed
    @debug "The determine step needed $elapsed seconds"

    elapsed = @elapsed begin
        step_all_entities(world, time_step_s)
    end

    global elapsed_step
    elapsed_step += elapsed
    @debug "The steps enti step needed $elapsed seconds"

    elapsed = @elapsed begin
        # now we process everything which happened in the steps,
        # tasks and previous iterations
        while state_changed
            @debug "Start simulation iteration"
            task_iter_result = nothing
            comm_iter_result = nothing
            @sync begin

                Threads.@spawn try
                    comm_iter_result = cs_step_iteration(world, time_step_s, first_step ? comm_result : nothing)
                catch ex
                    log_exception(ex)
                    rethrow(ex)
                end

                Threads.@spawn try
                    task_iter_result = step_iteration(world.task_sim, time_step_s, first_step)
                catch ex
                    log_exception(ex)
                    rethrow(ex)
                end
            end
            first_step = false
            push!(task_sim_result.results, task_iter_result)
            push!(messaging_sim_result.results, comm_iter_result)
            state_changed = comm_iter_result.state_changed || task_iter_result.state_changed
            @debug "Finish simulation iteration" state_changed
        end
    end

    global elapsed_sim
    elapsed_sim += elapsed
    @debug "The simulation step needed $elapsed seconds"
    
    elapsed = @elapsed begin
        world.clock.simulation_time = add_seconds(time(world), time_step_s)
        world.container.step_size_s = 0

        @debug "New time" time(world)

        do_recordings(world)
    end

    global elapsed_rec
    elapsed_rec += elapsed
    @debug "The recording update step needed $elapsed seconds"

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
    global elapsed_det, elapsed_step, elapsed_sim, elapsed_rec
    elapsed_det = elapsed_rec = elapsed_sim = elapsed_step = 0

    initial_time = time(world)
    prev_time = nothing
    results = []
    max_time = add_seconds(initial_time, max_advance_time_s)

    elapsed = @elapsed begin
        while isnothing(prev_time) || ((prev_time < time(world) || length(results) == 1)
                                       &&
                                       max_time > time(world))

            prev_time = time(world)
            push!(results, step_simulation(world, max_advance_time_s=(max_time - prev_time).value / 1000))
        end
    end
    @info "The discrete event simulation needed $elapsed seconds"
    @info "The different parts needed" elapsed_det elapsed_step elapsed_sim elapsed_rec

    return results
end

function discrete_step_until(world::World, max_advance::Dates.Period)
    return discrete_step_until(world, Second(max_advance).value)
end

struct NonWaitable end
function Base.wait(waitable::NonWaitable) end

function env(world::World)
    return world.env
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

function register(
    world::World,
    agent::Agent,
    suggested_aid::Union{String,Nothing}=nothing;
    kwargs...,
)
    if !isnothing(world.task_sim)
        agent.scheduler = create_agent_scheduler(world.task_sim)
    end
    agent = register(world.container, agent, suggested_aid, kwargs...)
    return agent
end

"""
    data_collection(world::World, key::String)

Return the data collection with the `key` from the world.
"""
function data_collection(world::World, key::String; no_plot::Bool=false)
    return get!(world.data_collections, key, WorldRecording(no_plot=no_plot))
end

"""
    data_agent_collection(world::World, key::String)

Return the data collection with the `key` from the world.
"""
function data_agent_collection(world::World, key::String; dedicated_plots::Bool=false, no_plot::Bool=false)
    return get!(world.data_agent_collections, key, AgentsRecording(dedicated_plots=dedicated_plots, no_plot=no_plot))
end


"""
    agent_recording_as_plottable(world::World, key::String)

Recording of agents as plottables values, Returns: x, ys, labels
"""
function agent_recording_as_plottable(world::World, key::String)
    agents_recording = data_agent_collection(world, key)
    labels, ys = get_labels_and_ys(agents_recording)
    return get_x(agents_recording), ys, labels
end

function agent_recordings_as_dict(world::World)
    d::OrderedDict{String, AgentsRecording} = world.data_agent_collections
    pairs::Vector{Pair} = []
    for (key, value) in d
        for (var, series) in value.timeseries
            push!(pairs, "$key-$var" => series)
        end
    end
    push!(pairs, "time" => collect(values(d))[1].time)
    return Dict(pairs)
end

"""
    collect_data(collector::Function, world::World, key::String)

Collect data from the world using the `collector` function and 
store it in the data collection with the `key`.
"""
function collect_data(collector::Function, world::World, key::String; no_plot::Bool=false)
    push!(world.data_collectors, (world) -> collector(world, data_collection(world, key, no_plot=no_plot)))
end

"""
    collect_agent_data(collector::Function, world::World, key::String)

Collect data from the agents in the world using the `collector` function and 
store it in the data collection with the `key`.

The data can be plotted using plot_agents.
"""
function collect_agent_data(collector::Function, world::World, key::String; dedicated_plots::Bool=false, no_plot::Bool=false) 
    dac = data_agent_collection(world, key, dedicated_plots=dedicated_plots, no_plot=no_plot)
    for agent in values(agents(world))
        push!(world.data_collectors, (world) -> collector(world, agent, dac))
    end
    push!(world.data_collectors, (world) -> push!(dac.time, seconds_elapsed(clock(world))))
end

"""
    record_world!(world_recorder::Function, world::World, key::String)

Record the world using the `world_recorder` function and store it in the data collection with the `key`.

The data can be plotted using plot_world.
"""
function record_world!(world_recorder::Function, world::World, key::String; no_plot::Bool=false)
    collect_data(world, key, no_plot=no_plot) do w, dc
        insert_world_recording!(dc, w, world_recorder())
    end
end

"""
    record_agent!(agent_recorder::Function, world::World, key::String)

Record the agents in the world using the `agent_recorder` function and store 
it in the data collection with the `key`. The data can be plotted using plot_agents.

"""
function record_agent!(agent_recorder::Function, world::World, key::String; dedicated_plots::Bool=false, no_plot::Bool=false)
    collect_agent_data(world, key, dedicated_plots=dedicated_plots, no_plot=no_plot) do w, a, dc
        insert_agent_recording!(dc, w, a, agent_recorder(a))
    end
end

function record_agent_having!(agent_recorder::Function, 
    world::World, 
    key::String, 
    role_type::DataType; 
    agent_color::Union{Nothing,Symbol}=nothing, 
    aid_contains::Union{Nothing,String}=nothing,
    dedicated_plots::Bool=false)

    collect_agent_data(world, key, dedicated_plots=dedicated_plots) do w, a, dc
        if has_role(a, role_type) &&
           (isnothing(agent_color) || agent_color == color(a)) && 
           (isnothing(aid_contains) || occursin(aid_contains, aid(a)))

            insert_agent_recording!(dc, w, a, agent_recorder(a))
        end
    end
end

"""
    record_position!(world::World, key::String="positions"; filter::Union{Nothing,Function}=nothing)

Record the spatial position of every agent that has a location in the world's space after
each simulation step, using the same data-collection infrastructure as [`record_agent!`](@ref).

An optional `filter` function `(agent) -> Bool` restricts recording to a subset of agents.
The recorded data is stored as `Position2D` values and is accessible via
[`position_history`](@ref) or [`data_agent_collection`](@ref).

# Example
```julia
record_position!(world)                               # all agents in the space
record_position!(world, filter = a -> a isa EVAgent)  # only EVAgents

pos = position_history(world)
pos.timeseries[aid(ev1)]   # Vector{Position2D} — one entry per step
pos.time                   # Vector of elapsed seconds at each snapshot
```
"""
function record_position!(world::World, key::String="positions";
                          filter::Union{Nothing,Function}=nothing)
    sp = space(world.env)
    collect_agent_data(world, key, no_plot=true) do w, a, dc
        if has_position(sp, a) && (isnothing(filter) || filter(a))
            insert_agent_recording!(dc, w, a, location(sp, a))
        end
    end
end

"""
    position_history(world::World, key::String="positions")

Return the [`AgentsRecording`](@ref) populated by [`record_position!`](@ref).

`timeseries` maps each agent AID to a `Vector{Position2D}` (one entry per simulation step).
`time` holds the elapsed seconds at each snapshot, aligned across all agents.
"""
function position_history(world::World, key::String="positions")
    return data_agent_collection(world, key)
end

function Base.getindex(world::World, index::String)
    return world.container[index]
end

function Base.getindex(world::World, index::Int)
    return world.container[index]
end

function shutdown(world::World)
    shutdown(world.container)
end
