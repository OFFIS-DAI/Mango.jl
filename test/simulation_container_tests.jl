using Mango
using Test
using Dates

import Mango.handle_message

@agent struct SimAgent
    counter::Int
end
function handle_message(agent::SimAgent, message::Any, meta::AbstractDict)
    agent.counter += 10
end
@testset "SimpleInternalSimulationWithoutDelayContainerTest" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2)

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 10
    @test agent2.counter == 10
end

@testset "SimpleInternalSimulationDelayGreaterStepSize" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=2))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2)

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 0
    @test agent2.counter == 0
    
    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 10
    @test agent2.counter == 10
end

@testset "SimpleInternalSimulationDelayMixedGreaterStepSize" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=2))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2)

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 0
    @test agent2.counter == 0

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))
    
    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 10
    @test agent2.counter == 10

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 20
    @test agent2.counter == 20
end