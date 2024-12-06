export Environment, Space, Position, Position2D, Area2D, location,
    move, initialize, initialized, Behavior, schedule, WorldObserver,
    emit_global_event, env

abstract type Position end
abstract type Space{P<:Position} end
abstract type WorldObserver end
abstract type Behavior end

function dispatch_global_event(observer::WorldObserver, event::Any)
    # default no reaction
end

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
Struct Environment. The environment is meant to provide a description of everything which exists outside of the agents.

The environment is a separate entity, which describes some type of environment, this can be anything which exists in
any type of space, this can be some model/evironment, which is observed by the agents. The agents can interact
with the environment and exist in the defined space.  
"""
@kwdef mutable struct Environment{S<:Space}
    scheduler::SimulationScheduler
    space::S = Area2D(width=10, height=10)
    behavior::Behavior = NoBehavior()
    observers::Vector{WorldObserver} = Vector{WorldObserver}()
    data_selectors::Vector{Function} = Vector{Function}()
    initialized::Bool = false
end

schedule(f::Function, environment::Environment, data::TaskData) = schedule(f, environment.scheduler, data)

"""
    on_step(environment::Environment, clock::Clock, step_size_s::Real)

Called on stepping the container.
"""
function on_step(environment::Environment, clock::Clock, step_size_s::Real)
    # default do nothing
end

"""
    on_step(behavior::Behavior, environment::Environment, clock::Clock, step_size_s::Real)

Called on stepping the container.
"""
function on_step(behavior::Behavior, environment::Environment, clock::Clock, step_size_s::Real)
    # default do nothing
end

function step(env::Environment, clock::Clock, step_size_s::Real)
    on_step(env, clock, step_size_s)
    on_step(behavior(env), env, clock, step_size_s)
end

"""
    location(space::Area2D, agent::Agent)::Position2D

Return the location of the `agent`.
"""
function location(space::Space{P}, agent::Agent)::P where {P<:Position}
    throw("Position on the space $space not defined!")
end

function location(space::Area2D, agent::Agent)::Position2D
    return space.to_position[aid(agent)]
end

"""
    move(space::Space{P}, agent::Agent, position::P) where {P<:Position}

Move the `agent` to `position` in `space`. 
"""
function move(space::Space{P}, agent::Agent, position::P) where {P<:Position}
    throw("Move on the space $space not defined!")
end

function move(space::Area2D, agent::Agent, position::Position2D)
    space.to_position[aid(agent)] = position
end

function initialize(space::Space, agents::Vector{A}) where {A<:Agent}
    throw("Initialization for $space is not defined!")
end

function initialize(space::Area2D, agents::Vector{A}) where {A<:Agent}
    for agent in agents
        space.to_position[aid(agent)] = Position2D(rand() * space.width, rand() * space.height)
    end
end

function initialize(environment::Environment{S}, agents::Vector{A}) where {S<:Space} where {A<:Agent}
    initialize(environment.space, agents)
end

"""
    initialized(environment::Environment)

Return whether the environment is intialized.
"""
function initialized(environment::Environment)
    return environment.initialized
end

"""
    add_observer!(environment::Environment, observer::WorldObserver)

Add an observer to the environment, which is able to handle 
global event emitted by the environment.
"""
function add_observer!(environment::Environment, observer::WorldObserver)
    push!(environment.observers, observer)
end

"""
    behavior(env::Environment)

Return the behavior of the environment.
"""
function behavior(env::Environment)
    return env.behavior
end

"""
    emit_global_event(environment::Environment, event::Any)

Emit an global event. This types of events can be handled by any agent
living in the environment (resp. living in the world, the environment exists in).
Therefore, any of those agents (and roles) can handle event emitted with
this function by defining [`on_global_event`](@ref).
"""
function emit_global_event(environment::Environment, event::Any)
    for observer in environment.observers
        dispatch_global_event(observer, event)
    end
end

"""
    select(environment::Environment, selector::Function)

Select an output attribute, which will be recorded while
the simulation is running (every step!).
"""
function select!(environment::Environment, selector::Function)
    push!(environment.data_selectors, selector)
end