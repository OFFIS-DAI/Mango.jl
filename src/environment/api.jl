export Position, Space, WorldObserver, Behavior, Environment

abstract type Position end
abstract type Space{P<:Position} end
abstract type WorldObserver end
abstract type Behavior end
abstract type Environment end

struct NoEnv <: Environment end

function dispatch_global_event(observer::WorldObserver, event::Any)
    # default no reaction
end

"""
    move(space::Space{P}, agent::Agent, position::P) where {P<:Position}

Move the `agent` to `position` in `space`. 
"""
function move(space::Space{P}, agent::Agent, position::P) where {P<:Position}
    throw("Move on the space $space not defined!")
end

function initialize(space::Space, agents::Vector{A}) where {A<:Agent}
    throw("Initialization for $space is not defined!")
end

"""
    location(space::Area2D, agent::Agent)::Position2D

Return the location of the `agent`.
"""
function location(space::Space{P}, agent::Agent)::P where {P<:Position}
    throw("Position on the space $space not defined!")
end

function schedule(f::Function, environment::Environment, data::TaskData) 
    # default do nothing
end

function step(environment::Environment, clock::Clock, step_size_s::Real)
    # default do nothing
end

function initialize(environment::Environment, agents::Vector{A}) where {A<:Agent}
    # default do nothing
end

function initialized(environment::Environment)
    # default do nothing
end

"""
    add_observer!(environment::Environment, observer::WorldObserver)

Add an observer to the environment, which is able to handle 
global event emitted by the environment.
"""
function add_observer!(environment::Environment, observer::WorldObserver)
    throw("Add observer not implemented for $environment")
end

"""
    emit_global_event(environment::Environment, event::Any)

Emit an global event. This types of events can be handled by any agent
living in the environment (resp. living in the world, the environment exists in).
Therefore, any of those agents (and roles) can handle event emitted with
this function by defining [`on_global_event`](@ref).
"""
function emit_global_event(environment::Environment, event::Any)
    throw("Emit global event not implemented for $environment")
end