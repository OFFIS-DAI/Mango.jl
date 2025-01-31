using Mango
using Test
using Logging
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

@testset "WorldKwargs" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2)

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid), test=2)

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 11
end

@testset "WorldNoProtocolSpecificAddr" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))

    @test isnothing(protocol_addr(world))
end

@testset "WorldNoValidTargetCustomAid" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2, "a1")

    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid="abc"))

    @test_logs (:warn, "Container $(keys(world.container.agents)) has no agent with id: abc") min_level = Logging.Warn begin
        stepping_result = step_simulation(world, 1)
    end

    @test agent1.counter == 0
    @test agent2.counter == 0
    @test aid(agent2) == "a1"
end

@testset "SimpleInternalSimulationWithoutDelayContainerTest" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=0))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2)

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)


    @test agent1.counter == 10
    @test agent2.counter == 10

    shutdown(world.container)
    @test world.container.shutdown
end

@testset "SimpleInternalSimulationDelayGreaterStepSize" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=2))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2)

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 0
    @test agent2.counter == 0

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 10
    @test agent2.counter == 10
end

@testset "SimpleInternalSimulationDelayMixedGreaterStepSize" begin

    world = create_world(DateTime(Millisecond(23)), communication_sim=SimpleCommunicationSimulation(default_delay_s=2))
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2)

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 0
    @test agent2.counter == 0

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 10
    @test agent2.counter == 10

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 20
    @test agent2.counter == 20
end

@testset "SimpleInternalSimulationLinkSpecificDelay" begin

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(Millisecond(0)), communication_sim=com_sim)
    agent1 = SimAgent(0)
    agent2 = SimAgent(0)
    register(world, agent1)
    register(world, agent2)
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent2))] = 2

    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 10
    @test agent2.counter == 0

    stepping_result = step_simulation(world, 1)

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

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)
    agent1 = SimSchedulingAgent(0, 0)
    agent2 = SimSchedulingAgent(0, 0)
    register(world, agent1)
    register(world, agent2)
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent2))] = 2

    schedule(agent1, PeriodicTaskData(0.1)) do
        agent1.scheduled_counter += 1
    end
    schedule(agent1, InstantTaskData()) do
        agent1.scheduled_counter += 100
    end
    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 111
    @test agent2.counter == 0

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 121
    @test agent2.counter == 1
end

@agent struct ComplexSimSchedulingAgent
    counter::Int
    scheduled_counter::Int
end

function handle_message(agent::ComplexSimSchedulingAgent, message::Any, meta::AbstractDict)
    agent.counter += 1
    schedule(agent, InstantTaskData()) do
        agent.scheduled_counter += 100
    end
end

@testset "SimulationWithSpecificDelaysAndScheduledTasksOnHandle" begin

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)
    agent1 = ComplexSimSchedulingAgent(0, 0)
    agent2 = ComplexSimSchedulingAgent(0, 0)
    register(world, agent1)
    register(world, agent2)
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent2))] = 2

    schedule(agent1, PeriodicTaskData(0.1)) do
        agent1.scheduled_counter += 1
    end
    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid))
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 111
    @test agent2.counter == 0
    @test agent2.scheduled_counter == 0

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 121
    @test agent2.counter == 1
    @test agent2.scheduled_counter == 100
end

@agent struct MoreComplexSimSchedulingAgent
    counter::Int
    scheduled_counter::Int
end

function handle_message(agent::MoreComplexSimSchedulingAgent, message::Any, meta::AbstractDict)
    agent.counter += 1
    schedule(agent, InstantTaskData()) do
        agent.scheduled_counter += 100
        if message == "Hello Friends, this is RSc!"
            reply_to(agent, "ABC", meta)
        end
    end
end

@testset "SimulationWithSpecificDelaysWithReplyOnHandle" begin

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)
    agent1 = MoreComplexSimSchedulingAgent(0, 0)
    agent2 = MoreComplexSimSchedulingAgent(0, 0)
    register(world, agent1)
    register(world, agent2)
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent1))] = 1
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent2))] = 2

    schedule(agent1, PeriodicTaskData(0.1)) do
        agent1.scheduled_counter += 1
    end
    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid), agent2.aid)
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 111
    @test agent2.counter == 1
    @test agent2.scheduled_counter == 100

    stepping_result = step_simulation(world, 1)

    @test agent1.counter == 1
    @test agent1.scheduled_counter == 121
    @test agent2.counter == 2
    @test agent2.scheduled_counter == 200
end

@testset "SimulationWithSpecificDelaysWithReplyOnHandleDiscreteEvent" begin

    com_sim = SimpleCommunicationSimulation(default_delay_s=0)
    world = create_world(DateTime(0), communication_sim=com_sim)
    agent1 = MoreComplexSimSchedulingAgent(0, 0)
    agent2 = MoreComplexSimSchedulingAgent(0, 0)
    register(world, agent1)
    register(world, agent2)
    com_sim.delay_s_directed_edge_dict[(aid(agent2), aid(agent1))] = 1
    com_sim.delay_s_directed_edge_dict[(nothing, aid(agent2))] = 2

    schedule(agent1, InstantTaskData()) do
        agent1.scheduled_counter += 1
    end
    schedule(agent1, InstantTaskData()) do
        agent1.scheduled_counter += 1
    end
    send_message(world.container, "Hello Friends, this is RSc!", AgentAddress(aid=agent1.aid), agent2.aid)
    send_message(world.container, "Hello Friends, this is RSd!", AgentAddress(aid=agent2.aid))

    stepping_result = step_simulation(world)

    @test stepping_result.simulation_step_size_s == 0
    @test agent1.counter == 0
    @test agent1.scheduled_counter == 2
    @test agent2.counter == 0
    @test agent2.scheduled_counter == 0

    stepping_result = step_simulation(world)

    @test stepping_result.simulation_step_size_s == 1
    @test agent1.counter == 1
    @test agent1.scheduled_counter == 102
    @test agent2.counter == 1
    @test agent2.scheduled_counter == 100

    stepping_result = step_simulation(world)

    @test stepping_result.simulation_step_size_s == 1
    @test agent1.counter == 1
    @test agent1.scheduled_counter == 102
    @test agent2.counter == 2
    @test agent2.scheduled_counter == 200

    stepping_result = step_simulation(world)

    @test isnothing(stepping_result)

    schedule(agent1, PeriodicTaskData(0.1)) do
        agent1.scheduled_counter += 1
    end
    schedule(agent1, PeriodicTaskData(3)) do
        # nothing
    end

    stepping_result = step_simulation(world)

    @test stepping_result.simulation_step_size_s == 0
    @test agent1.counter == 1
    @test agent1.scheduled_counter == 103
    @test agent2.counter == 2
    @test agent2.scheduled_counter == 200

    stepping_result = step_simulation(world)

    @test stepping_result.simulation_step_size_s == 0.1
    @test agent1.counter == 1
    @test agent1.scheduled_counter == 104
    @test agent2.counter == 2
    @test agent2.scheduled_counter == 200
end

import Mango

@testset "SimulationSchedulerDetermineError" begin
    s = SimulationScheduler(clock=Clock(DateTime(0)))
    push!(s.queue, Task(""))

    @test_throws "This should not happen! Did you schedule a task with zero sleep time?" Mango.determine_next_event_time_with(s, DateTime(0))
end

struct TestTaskSim <: TaskSimulation
end

@testset "SimulationSchedulerDetermineNoImplent" begin
    @test_throws "Please implement determine_next_event_time(...)" Mango.determine_next_event_time(TestTaskSim())
end

@testset "WorldAgentsAreOrdered" begin
    world = create_world(DateTime(0))
    a1 = register(world, SimAgent(0))
    a2 = register(world, SimAgent(1))
    a3 = register(world, SimAgent(2))
    a4 = register(world, SimAgent(3))

    @test agents(world)[1] == a1
    @test agents(world)[2] == a2
    @test agents(world)[3] == a3
    @test agents(world)[4] == a4
    @test world[aid(a1)] == a1
    @test world[1] == a1
end


@agent struct ErrorAgent
    counter::Int
end

function handle_message(agent::ErrorAgent, message::Any, meta::AbstractDict)
    throw("Something")
end

@testset "WorldTestExceptionInScheduledTask" begin
    world = create_world(DateTime(0))

    activate(world) do 
        schedule(env(world), DelayTaskData(1)) do 
            throw("Noooo")
        end 
        step_simulation(world) # start scheduling = 0
        @test_throws CompositeException step_simulation(world) # schedule task = 1
    end

end

@testset "WorldTestExceptionInMessageHandling" begin
    world = create_world(DateTime(0))
    a1 = register(world, ErrorAgent(0))
    a2 = register(world, ErrorAgent(0))

    activate(world) do 
        send_message(a1, "1", address(a2))
        @test_throws CompositeException step_simulation(world) # schedule task = 1
    end
end