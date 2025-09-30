export observation, actions, action, install_action, install_observer

mutable struct ObservationService 
    observers::Dict{Symbol,Function}
end

function observe(observation_service::ObservationService, symbol::Symbol)
    return observation_service.observers[symbol]()
end

function observation(agent::Agent, symbol::Symbol=:default)::Any
    return observe(service_of_type(agent, ObservationService, ObservationService(Dict())), symbol)
end

function observation(role::Role, symbol::Symbol=:default)::Any
    return observation(role.context.agent, symbol)
end

function install_observer(observer::Function, agent::Agent, symbol::Symbol=:default)
    s = service_of_type(agent, ObservationService, ObservationService(Dict()))
    s.observers[symbol] = observer
end

struct ActionService
    actions::Dict{Symbol,Function}
end

function actions(action_service::ActionService)
    return action_service.actions
end

function actions(agent::Agent)::Dict{Symbol,Function}
    return actions(service_of_type(agent, ActionService, ActionService(Dict())))
end

function action(agent::Agent, symbol::Symbol)::Function
    return actions(agent)[symbol]
end

function actions(role::Role)::Dict{Symbol,Function}
    return actions(role.context.agent)
end

function action(role::Role, symbol::Symbol)::Function
    return actions(role)[symbol]
end

function install_action(action::Function, agent::Agent, symbol::Symbol)
    s = service_of_type(agent, ActionService, ActionService(Dict()))
    s.actions[symbol] = action
end