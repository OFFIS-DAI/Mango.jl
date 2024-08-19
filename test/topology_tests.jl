using Mango
using Test

@agent struct TopologyAgent
end

@testset "TestTopologyInjectsService" begin
    topology = complete_topology(3)
    container = create_tcp_container("127.0.0.1", 3333)
    agent = nothing

    per_node(topology) do node
        agent = register(container, TopologyAgent())
        add!(node, agent)
    end

    activate(container) do
        send_message(container, "Yo", address(agent))
    end

    @test topology_neighbors(agent) == [address(agents(container)[1]),
        address(agents(container)[2])]
end

@testset "TestCreateTopology" begin
    container = create_tcp_container("127.0.0.1", 3333)
    agent = nothing

    create_topology() do topology
        agent = register(container, TopologyAgent())
        agent2 = register(container, TopologyAgent())
        agent3 = register(container, TopologyAgent())
        n1 = add_node!(topology, agent)
        n2 = add_node!(topology, agent2)
        n3 = add_node!(topology, agent3)
        add_edge!(topology, n1, n2)
        add_edge!(topology, n1, n3)
    end

    @test topology_neighbors(agent) == [address(agents(container)[2]),
        address(agents(container)[3])]
    @test topology_neighbors(agents(container)[2]) == [address(agents(container)[1])]
    @test topology_neighbors(agents(container)[3]) == [address(agents(container)[1])]
end

@testset "TestOtherBuiltInTopologies" begin
    topology = star_topology(4)
    container = create_tcp_container("127.0.0.1", 3333)

    per_node(topology) do node
        add!(node, register(container, TopologyAgent()))
    end

    topology = cycle_topology(4)
    per_node(topology) do node
        add!(node, register(container, TopologyAgent()))
    end

    @test length(topology_neighbors(agents(container)[5])) == 2
    @test length(topology_neighbors(agents(container)[6])) == 2
    @test length(topology_neighbors(agents(container)[7])) == 2
    @test length(topology_neighbors(agents(container)[8])) == 2
end