export DefaultEnvironment, Position2D, Area2D, location,
    move, initialize, initialized, schedule,
    emit_global_event, behavior, space, install, emit_agent_event,
    has_position, distance, agents_within, move_toward!

struct NoBehavior <: Behavior end

abstract type Space{P<:Position} end

"""
    move(space::Space{P}, agent::Agent, position::P) where {P<:Position}

Move the `agent` to `position` in `space`. 
"""
function move(space::Space{P}, agent::Agent, position::P) where {P<:Position}
    throw("Move on the space $space not defined!")
end


"""
    initialize(space::Space, agents::Vector{A}) where {A<:Agent}

Initializes the space.
"""
function initialize(space::Space, agents::Vector{A}, clock::Clock) where {A<:Agent}
    throw("Initialization for $space is not defined!")
end

"""
    install(space::Space{P}, agent::Agent; additional_information...) where {P<:Position}

Install the agent on the space.
"""
function install(space::Space{P}, agent::Agent; id::Any,  additional_information...) where {P<:Position}
    # do nothing by default
end

"""
    location(space::Area2D, agent::Agent)::Position2D

Return the location of the `agent`.
"""
function location(space::Space{P}, agent::Agent)::P where {P<:Position}
    throw("Position on the space $space not defined!")
end

struct Position2D <: Position
    x::Real
    y::Real
end

"""
    has_position(space::Space, agent::Agent) -> Bool

Return `true` if `agent` currently has a registered position in `space`.

The default implementation returns `false`; concrete `Space` subtypes should
override this method.
"""
has_position(::Space, ::Agent) = false

@kwdef struct Area2D <: Space{Position2D}
    width::Real
    height::Real
    to_position::Dict{String,Position2D} = Dict()
end

"""
Struct DefaultEnvironment. The environment provides a description of everything which exists outside of the agents.

The environment is a separate entity, which describes some type of environment, this can be anything which exists in
any type of space, this can be some model/evironment, which is observed by the agents. The agents can interact
with the environment and exist in the defined space.  
"""
@kwdef mutable struct DefaultEnvironment{S<:Space} <: Environment
    scheduler::SimulationScheduler
    space::S = Area2D(width=10, height=10)
    behavior::Behavior = NoBehavior()
    observers::Vector{WorldObserver} = Vector{WorldObserver}()
    installed_id_to_agent::Dict{Any, Agent} = Dict{Any, Agent}()
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

"""
    install(behavior::Behavior, agent::Agent; additional_information...)

Install the agent using the behavior data.
"""
function install(behavior::Behavior, agent::Agent; id::Any, additional_information...)
    # do nothing by default
end

function step(env::DefaultEnvironment, clock::Clock, step_size_s::Real)
    on_step(behavior(env), env, clock, step_size_s)
end

has_position(space::Area2D, agent::Agent) = haskey(space.to_position, aid(agent))

function location(space::Area2D, agent::Agent)::Position2D
    return space.to_position[aid(agent)]
end

function move(space::Area2D, agent::Agent, position::Position2D)
    space.to_position[aid(agent)] = position
end

function initialize(space::Area2D, agents::Vector{A}, clock::Clock) where {A<:Agent}
    for agent in agents
        if !haskey(space.to_position, aid(agent)) 
            space.to_position[aid(agent)] = Position2D(rand() * space.width, rand() * space.height)
        end
    end
end

function initialize(behavior::Behavior, env::Environment, clock::Clock)
    # default no initialization
end

function initialize(environment::DefaultEnvironment{S}, agents::Vector{A}, clock::Clock) where {S<:Space} where {A<:Agent}
    initialize(environment.space, agents, clock)
    initialize(behavior(environment), environment, clock)
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
    space(env::DefaultEnvironment)

The space of the environment
"""
function space(env::DefaultEnvironment)
    return env.space
end

"""
    emit_global_event(environment::DefaultEnvironment, event::Any)

Emit a global event. This types of events can be handled by any agent
living in the environment (resp. living in the world, the environment exists in).
Therefore, any of those agents (and roles) can handle events emitted with
this function by defining [`on_global_event`](@ref).
"""
function emit_global_event(environment::DefaultEnvironment, event::Any)
    for observer in environment.observers
        dispatch_global_event(observer, environment.scheduler.clock, event)
    end
end

function install(environment::DefaultEnvironment, agent::A; id::Any, additional_information...) where {A<:Agent}
    install(space(environment), agent; id=id, additional_information...)
    install(behavior(environment), agent; id=id, additional_information...)
    environment.installed_id_to_agent[id] = agent
end

function emit_agent_event(environment::DefaultEnvironment, event::Any, id::Any)
    if haskey(environment.installed_id_to_agent, id)
        agent = environment.installed_id_to_agent[id]
        on_agent_event(agent, environment.scheduler.clock, event)
        for role in roles(agent)
            on_agent_event(role, environment.scheduler.clock, event)
        end
    else
        @debug "You are calling emit_agent_event although no agent is installed on the ID" id
    end
end

"""
    distance(pa::Position2D, pb::Position2D)::Float64

Return the Euclidean distance between two `Position2D` points.
"""
function distance(pa::Position2D, pb::Position2D)::Float64
    return sqrt((pa.x - pb.x)^2 + (pa.y - pb.y)^2)
end

"""
    distance(space::Area2D, agent_a::Agent, agent_b::Agent)::Float64

Return the Euclidean distance between the current positions of `agent_a` and `agent_b`
in `space`. Both agents must have a registered position.
"""
function distance(space::Area2D, agent_a::Agent, agent_b::Agent)::Float64
    return distance(location(space, agent_a), location(space, agent_b))
end

"""
    agents_within(space::Area2D, center::Position2D, radius::Real, agent_list)

Return all agents from `agent_list` whose registered position in `space` is within
`radius` of `center`. Agents without a registered position are excluded.

# Example
```julia
nearby = agents_within(space(world), location(space(world), hub), 5.0, agents(world))
```
"""
function agents_within(space::Area2D, center::Position2D, radius::Real, agent_list)
    return filter(a -> has_position(space, a) && distance(location(space, a), center) <= radius,
                  agent_list)
end

"""
    move_toward!(space::Area2D, agent::Agent, target::Position2D, max_step::Real)

Move `agent` toward `target` by at most `max_step` units. If the agent is already
within `max_step` of `target` it is placed exactly at `target`.

# Example
```julia
function Mango.on_step(agent::RoverAgent, env::Environment, clock::Clock, step_size_s::Real)
    move_toward!(env.space, agent, agent.goal, agent.speed * step_size_s)
end
```
"""
function move_toward!(space::Area2D, agent::Agent, target::Position2D, max_step::Real)
    current = location(space, agent)
    d = distance(current, target)
    if d <= max_step || d == 0
        move(space, agent, target)
    else
        ratio = max_step / d
        move(space, agent, Position2D(current.x + ratio * (target.x - current.x),
                                      current.y + ratio * (target.y - current.y)))
    end
end
