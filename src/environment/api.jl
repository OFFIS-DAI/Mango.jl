export Position, Space, WorldObserver, Behavior

abstract type Position end
abstract type Space{P<:Position} end
abstract type WorldObserver end
abstract type Behavior end
abstract type EnvironmentInterface end

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