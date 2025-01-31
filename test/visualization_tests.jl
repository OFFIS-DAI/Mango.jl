using Mango
using Test
using Graphs
using Dates
using CairoMakie

@agent struct TopologyPlotAgent
end

@agent struct MyVisuBehavingAgent
    counter::Int
    other_aid::String
end

function Mango.on_step(agent::MyVisuBehavingAgent, environment::Environment, clock::Clock, step_size_s::Real)
    if agent.counter > 10
        return
    end
    agent.counter += 1
    send_message(agent, "Trigger", AgentAddress(aid=agent.other_aid))
end

@testset "TestVisuAgents" begin
    world = create_world(DateTime(Millisecond(0)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=1))

    agent1 = register(world, MyVisuBehavingAgent(0, "2"), "1")
    agent2 = register(world, MyVisuBehavingAgent(0, "1"), "2")

    record_agent!((agent) -> agent.counter, world, "counter")
    record_world!(() -> Second(world.clock.simulation_time).value, world, "time")

    activate(world) do
        results = discrete_step_until(world, 1000)
    end

    plot_world(world, "time", write_to="test_world_plot.svg")
    plot_agents(world, "counter", write_to="test_agents_plot.svg")
    plot_recordings(world, size=(800, 800), write_to="test_recordings_plot.svg")

    open("test_world_plot.svg", "r") do f
        @test length(read(f, String)) > 1000
    end
    rm("test_world_plot.svg")

    open("test_agents_plot.svg", "r") do f
        @test length(read(f, String)) > 1000
    end
    rm("test_agents_plot.svg")

    open("test_recordings_plot.svg", "r") do f
        @test length(read(f, String)) > 1000
    end
    rm("test_recordings_plot.svg")
end

@testset "TestVisuAgentsComm" begin
    world = create_world(DateTime(Millisecond(0)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=1))

    agent1 = register(world, MyVisuBehavingAgent(0, "2"), "1")
    agent2 = register(world, MyVisuBehavingAgent(0, "1"), "2")

    topology = complete_topology(2)
    auto_assign!(topology, world)

    activate(world) do
        results = discrete_step_until(world, 1000)
    end

    show_communication_data(topology, world, show=false)
    rm("communication.svg")
end

@testset "TestVisuAgentsTopo" begin
    world = create_world(DateTime(Millisecond(0)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=1))

    agent1 = register(world, MyVisuBehavingAgent(0, "2"), "1")
    agent2 = register(world, MyVisuBehavingAgent(0, "1"), "2")

    topology = complete_topology(3)
    auto_assign!(topology, world)

    plot_topology(topology, write_to="test_topology_plot.svg")
    rm("test_topology_plot.svg")
end