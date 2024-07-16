using Mango
using Test
using Dates

import Mango.handle_message


@agent struct SimAgent
    counter::Int
end

function handle_message(agent::SimAgent, message::Any, meta::AbstractDict)
    agent.counter += 10
    if haskey(meta, "test")
        agent.counter += 1
    end
end

@testset "SimulationContainerKwargs" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2)

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid), test=2)

    stepping_result = step_simulation(container, 1)

    shutdown(container)

    @test agent1.counter == 11
end

@testset "SimulationContainerNoProtocolSpecificAddr" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))

    @test isnothing(protocol_addr(container))
end

@testset "SimulationContainerNoValidTargetCustomAid" begin

    container = create_simulation_container(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2, "a1")

    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid="abc"))

    @test_logs (:warn, "Container $(keys(container.agents)) has no agent with id: abc") begin
        stepping_result = step_simulation(container, 1)
    end

    @test agent1.counter == 0
    @test agent2.counter == 0
    @test aid(agent2) == "a1"
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

    shutdown(container)

    @test agent1.counter == 10
    @test agent2.counter == 10
    @test container.shutdown
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

@testset "SimpleInternalSimulationLinkSpecificDelay" begin

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    container = create_simulation_container(DateTime(Millisecond(0)), communication_sim=com_sim)
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(container, agent1)
    register(container, agent2)
    com_sim.delay_s_directed_edge_vector[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_vector[(nothing, aid(agent2))] = 2

    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 10
    @test agent2.counter == 0

    stepping_result = step_simulation(container, 1)
    
    @test agent1.counter == 10
    @test agent2.counter == 10
    
end

@agent struct SimSchedulingAgent
    counter::Int
    scheduled_counter::Int
end

function handle_message(agent::SimSchedulingAgent, message::Any, meta::AbstractDict)
    agent.counter += 1
end

@testset "SimulationWithSpecificDelaysAndScheduledTasks" begin
    using Logging

    debug_logger = ConsoleLogger(stderr, Logging.Debug)
    global_logger(debug_logger)

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    container = create_simulation_container(DateTime(0), communication_sim=com_sim)
    agent1 = SimSchedulingAgent(0, 0)
    agent2 = SimSchedulingAgent(0, 0)
    register(container, agent1)
    register(container, agent2)
    com_sim.delay_s_directed_edge_vector[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_vector[(nothing, aid(agent2))] = 2

    schedule(agent1, PeriodicTaskData(0.1)) do
        agent1.scheduled_counter += 1
    end
    send_message(container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(container, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 11
    @test agent2.counter == 0

    stepping_result = step_simulation(container, 1)
    
    @test agent1.counter == 1
    @test agent1.scheduled_counter == 21
    @test agent2.counter == 1
end