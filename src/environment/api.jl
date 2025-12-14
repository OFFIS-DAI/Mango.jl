export Position, Space, WorldObserver, Behavior, Environment, NoEnv, install, dispatch_global_event, initialize, initialized, add_observer!, emit_agent_event

abstract type Position end
abstract type WorldObserver end
abstract type Behavior end
abstract type Environment end

struct NoEnv <: Environment end

function dispatch_global_event(observer::WorldObserver, clock::Clock, event::Any)
    # default no reaction
end


"""
    schedule(f::Function, environment::Environment, data::TaskData)

Schedule a task for the given environment.
"""
function schedule(f::Function, environment::Environment, data::TaskData) 
    throw("Schedule is not implemented for $environment")
end

"""
    step(environment::Environment, clock::Clock, step_size_s::Real)

Step the environment for the given time and advancing step_size_s.
"""
function step(environment::Environment, clock::Clock, step_size_s::Real)
    throw("Step is not implemented for $environment")
end

"""
    initialize(environment::Environment, agents::Vector{A}) where {A<:Agent}

Initialize the environment. Should be called once per instantiated Environment.
"""
function initialize(environment::Environment, agents::Vector{A}, clock::Clock) where {A<:Agent}
    # default do nothing
end

"""
    initialized(environment::Environment)

Return true, if the environment is already initialized.
"""
function initialized(environment::Environment)
    throw("Initialized is not implemented for $environment")
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

"""
    install(environment::Environment, agent::A; id::Any, additional_information...) where {A<:Agent}

Install the agent to the environment using optional additional information. This method can
be used to 
"""
function install(environment::Environment, agent::A; id::Any, additional_information...) where {A<:Agent}
    throw("Install is not implemented for $environment")
end

"""
    emit_agent_event(environment::Environment, event::Any, id::Any)

Emits an agent event sent to all agentsm which are installed on `id`.
"""
function emit_agent_event(environment::Environment, clock::Clock, event::Any, id::Any)
    throw("Emit agent event not implemented for $environment")
end