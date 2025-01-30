export DefaultEnvironment, Position2D, Area2D, location,
    move, initialize, initialized, schedule,
    emit_global_event, behavior

struct NoBehavior <: Behavior end

struct Position2D <: Position
    x::Real
    y::Real
end

@kwdef struct Area2D <: Space{Position2D}
    width::Real
    height::Real
    to_position::Dict{String,Position2D} = Dict()
end

"""
Struct DefaultEnvironment. The environment is meant to provide a description of everything which exists outside of the agents.

The environment is a separate entity, which describes some type of environment, this can be anything which exists in
any type of space, this can be some model/evironment, which is observed by the agents. The agents can interact
with the environment and exist in the defined space.  
"""
@kwdef mutable struct DefaultEnvironment{S<:Space} <: Environment
    scheduler::SimulationScheduler
    space::S = Area2D(width=10, height=10)
    behavior::Behavior = NoBehavior()
    observers::Vector{WorldObserver} = Vector{WorldObserver}()
    initialized::Bool = false
end

schedule(f::Function, environment::DefaultEnvironment, data::TaskData) = schedule(f, environment.scheduler, data)

"""
    on_step(behavior::Behavior, environment::DefaultEnvironment, clock::Clock, step_size_s::Real)

Called on stepping the container.
"""
function on_step(behavior::Behavior, environment::DefaultEnvironment, clock::Clock, step_size_s::Real)
    # default do nothing
end

function step(env::DefaultEnvironment, clock::Clock, step_size_s::Real)
    on_step(behavior(env), env, clock, step_size_s)
end

function location(space::Area2D, agent::Agent)::Position2D
    return space.to_position[aid(agent)]
end


function move(space::Area2D, agent::Agent, position::Position2D)
    space.to_position[aid(agent)] = position
end

function initialize(space::Area2D, agents::Vector{A}) where {A<:Agent}
    for agent in agents
        space.to_position[aid(agent)] = Position2D(rand() * space.width, rand() * space.height)
    end
end

function initialize(behavior::Behavior)
    # default no initialization
end

function initialize(environment::DefaultEnvironment{S}, agents::Vector{A}) where {S<:Space} where {A<:Agent}
    initialize(environment.space, agents)
    initialize(behavior(environment))
    environment.initialized = true
end

"""
    initialized(environment::DefaultEnvironment)

Return whether the environment is intialized.
"""
function initialized(environment::DefaultEnvironment)
    return environment.initialized
end

"""
    add_observer!(environment::DefaultEnvironment, observer::WorldObserver)

Add an observer to the environment, which is able to handle 
global event emitted by the environment.
"""
function add_observer!(environment::DefaultEnvironment, observer::WorldObserver)
    push!(environment.observers, observer)
end

"""
    behavior(env::DefaultEnvironment)

Return the behavior of the environment.
"""
function behavior(env::DefaultEnvironment)
    return env.behavior
end

"""
    emit_global_event(environment::DefaultEnvironment, event::Any)

Emit an global event. This types of events can be handled by any agent
living in the environment (resp. living in the world, the environment exists in).
Therefore, any of those agents (and roles) can handle event emitted with
this function by defining [`on_global_event`](@ref).
"""
function emit_global_event(environment::DefaultEnvironment, event::Any)
    for observer in environment.observers
        dispatch_global_event(observer, event)
    end
end