using Mango
using Test
using Dates

import Mango.on_step

@agent struct ModellingAgent
    counter::Real
end

function on_step(agent::ModellingAgent, world::World, clock::Clock, step_size_s::Real)
    agent.counter += step_size_s
end

@testset "TestAgentIsStepped" begin
    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = ModellingAgent(0)
    agent2 = ModellingAgent(0)
    register(container, agent1)
    register(container, agent2)

    stepping_result = step_simulation(container, 7.1)

    shutdown(container)

    @test agent1.counter == 7.1
end

@role struct ModellingRole
    counter::Real
end

function on_step(role::ModellingRole, world::World, clock::Clock, step_size_s::Real)
    role.counter += step_size_s
end

@testset "TestAgentIsSteppedRole" begin
    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent = ModellingAgent(0)
    role = ModellingRole(0)
    register(container, agent)
    add(agent, role)

    stepping_result = step_simulation(container, 7.1)

    shutdown(container)

    @test role.counter == 7.1
end

@agent struct ModellingMovingAgent
    target::Position2D
    prev_position::Position2D
    position::Position2D
end

function on_step(agent::ModellingMovingAgent, world::World, clock::Clock, step_size_s::Real)
    agent.prev_position = location(world.space, agent)
    move(world.space, agent, agent.target)
    agent.position = location(world.space, agent)
end

@testset "TestAgentStepPosition" begin
    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    given_initial = Position2D(-1,-1)
    given_target = Position2D(1,1)
    agent = ModellingMovingAgent(given_target, given_initial, given_initial)
    register(container, agent)

    stepping_result = step_simulation(container, 1)

    shutdown(container)

    @test agent.prev_position != given_initial
    @test agent.position == given_target
end