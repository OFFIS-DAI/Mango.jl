export World, Space, Position, Position2D, Area2D, location, move, initialize, initialized

abstract type Position end
abstract type Space{P<:Position} end

struct Position2D <: Position
    x::Real
    y::Real
end

@kwdef struct Area2D <: Space{Position2D}
    width::Real
    height::Real
    to_position::Dict{String,Position2D}=Dict()
end

@kwdef struct World{S<:Space}
    space::S = Area2D(width=10,height=10)
    initialized::Bool = false
end

function location(space::Space{P}, agent::Agent)::P where P <: Position
    throw("Position on the space $space not defined!")
end

function location(space::Area2D, agent::Agent)::Position2D
    return space.to_position[aid(agent)]
end

function move(space::Space{P}, agent::Agent, position::P) where P <: Position
    throw("Move on the space $space not defined!")
end

function move(space::Area2D, agent::Agent, position::Position2D)
    space.to_position[aid(agent)] = position
end

function initialize(space::Space, agents::Vector{A}) where A <:Agent
    throw("Initialization for $space is not defined!")
end

function initialize(space::Area2D, agents::Vector{A}) where A <:Agent
    for agent in agents
        space.to_position[aid(agent)] = Position2D(rand()*space.width, rand()*space.height)
    end
end

function initialize(world::World{S}, agents::Vector{A}) where S <: Space where A <:Agent
    initialize(world.space, agents)
end

function initialized(world::World)
    return world.initialized
end