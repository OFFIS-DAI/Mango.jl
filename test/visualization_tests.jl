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

function Mango.on_step(agent::MyVisuBehavingAgent, environment::DefaultEnvironment, clock::Clock, step_size_s::Real)
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

    show_communication_data(world, show=false, based_on=topology)
    rm("communication.svg")
end

@testset "TestVisuAgentsTopo" begin
    world = create_world(DateTime(Millisecond(0)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=1))

    agent1 = register(world, MyVisuBehavingAgent(0, "2"), "1")
    agent2 = register(world, MyVisuBehavingAgent(0, "1"), "2")

    topology = complete_topology(3)
    auto_assign!(topology, world)

    plot_node_topology(topology, write_to="test_topology_plot.svg")
    rm("test_topology_plot.svg")
end


@testset "TestMultiTopo" begin
    world = create_world(DateTime(Millisecond(0)),
        communication_sim=SimpleCommunicationSimulation(default_delay_s=1))

    agent1 = register(world, MyVisuBehavingAgent(0, "2"), "1")
    agent2 = register(world, MyVisuBehavingAgent(0, "1"), "2")
    agent3 = register(world, MyVisuBehavingAgent(0, "3"), "3")
    mark_as_connector!(agent1)
    agent4 = register(world, MyVisuBehavingAgent(0, "4"), "4")
    agent5 = register(world, MyVisuBehavingAgent(0, "5"), "5")
    agent6 = register(world, MyVisuBehavingAgent(0, "6"), "6")
    mark_as_connector!(agent6)

    topology = complete_topology(3)
    topology2 = complete_topology(3)
    auto_assign!(topology, world)
    auto_assign!(topology2, world)
    connect_topologies!(topology, topology2)

    plot_multi_agent_topology([topology, topology2], write_to="test_topology_plot.svg")
    @test stat("test_topology_plot.svg").size == 13348
    rm("test_topology_plot.svg")
end