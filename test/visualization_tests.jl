using Mango
using Test
using Graphs
using Dates

@agent struct TopologyPlotAgent
end

@testset "TestTopologyPlotting" begin
    topology = create_topology() do topology
        n1 = add_node!(topology, TopologyPlotAgent())
        n2 = add_node!(topology, TopologyPlotAgent())
        n3 = add_node!(topology, TopologyPlotAgent(), id=12)
        add_edge!(topology, n1, n2)
        add_edge!(topology, n1, n3)
    end

    svg_string = plot(topology, write_to="test_topology_plot.svg")
    svg_string2 = plot(topology, annotate_aids=true)

    @test length(svg_string) > 10000
    @test length(svg_string2) > 20000

    rm("test_topology_plot.svg")
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

    show_communication_data(topology, world, display=false)
end