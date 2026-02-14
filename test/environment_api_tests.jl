using Mango
using Test
using Dates

@agent struct WorldEventAgent
    counter::Real
end

@role struct WorldEventRole
    counter::Real
end

function Mango.on_global_event(role::WorldEventRole, clock::Clock, event::String)
    role.counter += 7
end

function Mango.on_global_event(agent::WorldEventAgent, clock::Clock, event::String)
    agent.counter += 7
end

struct TestBehavior <: Behavior end

function Mango.on_step(behavior::TestBehavior, environment::DefaultEnvironment, clock::Clock, step_size_s::Real)
    emit_global_event(environment, "Hello Agent, I am the environment")
    
    schedule(environment, InstantTaskData()) do
        emit_global_event(environment, "Hello Agent, I am the environment")
    end
end

@testset "TestAgentWorldEvent" begin
    world = create_world(DateTime(Millisecond(23)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=0),
        behavior=TestBehavior())
    agent1 = WorldEventAgent(0)
    register(world, agent1)
    agent2 = add_agent_composed_of(world, WorldEventRole(1))

    stepping_result = step_simulation(world)
    @test agent1.counter == 7
    @test agent2[WorldEventRole].counter == 8
    stepping_result = step_simulation(world)
    @test agent1.counter == 28
    @test agent2[WorldEventRole].counter == 29
end

struct TestPosition <: Position end
struct TestSpace <: Space{TestPosition} end

@testset "TestAgentSpaceApiNotImplemented" begin
    test_space = TestSpace()
    agent = WorldEventAgent(12)  
    @test_throws "Initialization for TestSpace is not defined!" initialize(test_space, [agent], Mango.zero_clock())
    @test_throws "Move on the space TestSpace not defined!" move(test_space, agent, TestPosition())
    @test_throws "Position on the space TestSpace not defined!" location(test_space, agent)
end

@testset "TestNoEnvNoImpl" begin
    no_env = NoEnv()
    
    initialize(no_env, [WorldEventAgent(12)], Mango.zero_clock())
    @test_throws "Initialized is not implemented for NoEnv" initialized(no_env)
    @test_throws "Emit global event not implemented for NoEnv" emit_global_event(no_env, "")
end