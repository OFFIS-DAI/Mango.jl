using Mango
using Test
using Dates

@agent struct WorldEventAgent
    counter::Real
end
@role struct WorldEventRole
    counter::Real
end
function Mango.on_global_event(role::WorldEventRole, event::String)
    role.counter += 7
end
function Mango.on_global_event(agent::WorldEventAgent, event::String)
    agent.counter += 7
end

struct TestBehavior <: Behavior end

function Mango.on_step(behavior::TestBehavior, environment::Environment, clock::Clock, step_size_s::Real)
    emit_global_event(environment, "Hello Agent, I am the environment")
    schedule(environment, InstantTaskData()) do
        emit_global_event(environment, "Hello Agent, I am the environment")
    end
end

@testset "TestAgentWorldEvent" begin
    container = create_world(DateTime(Millisecond(23)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=0),
        behavior=TestBehavior())
    agent1 = WorldEventAgent(0)
    register(container, agent1)
    agent2 = add_agent_composed_of(container, WorldEventRole(1))

    stepping_result = step_simulation(container)
    @test agent1.counter == 14
    @test agent2[WorldEventRole].counter == 15
    stepping_result = step_simulation(container)
    @test agent1.counter == 28
    @test agent2[WorldEventRole].counter == 29
end