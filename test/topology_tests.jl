using Mango
using Test
using Graphs

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

@testset "TestModifyTopology" begin
    container = create_tcp_container("127.0.0.1", 3333)
    agent = nothing
    topology = cycle_topology(4)

    modify_topolology(topology) do topology
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

@testset "TestCreateTopologyDirected" begin
    container = create_tcp_container("127.0.0.1", 3333)
    agent = nothing

    create_topology(directed=true) do topology
        agent = register(container, TopologyAgent())
        agent2 = register(container, TopologyAgent())
        agent3 = register(container, TopologyAgent())
        n1 = add_node!(topology, agent)
        n2 = add_node!(topology, agent2)
        n3 = add_node!(topology, agent3)
        add_edge!(topology, n1, n2, directed=true)
        add_edge!(topology, n1, n3, directed=true)
    end

    @test topology_neighbors(agent) == [address(agents(container)[2]),
        address(agents(container)[3])]
    @test length(topology_neighbors(agents(container)[2])) == 0
    @test length(topology_neighbors(agents(container)[3])) == 0
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

@testset "TestCustomGraphTopology" begin
    cd = complete_digraph(5)
    topology = graph_topology(cd)
    container = create_tcp_container("127.0.0.1", 3333)

    per_node(topology) do node
        add!(node, register(container, TopologyAgent()))
    end

    @test length(topology_neighbors(agents(container)[1])) == 4
    @test length(topology_neighbors(agents(container)[2])) == 4
    @test length(topology_neighbors(agents(container)[3])) == 4
    @test length(topology_neighbors(agents(container)[4])) == 4
    @test length(topology_neighbors(agents(container)[5])) == 4
end

@role struct TopologyRole
end

@testset "TestCustomGraphTopologyRole" begin
    cd = complete_digraph(5)
    topology = graph_topology(cd)
    container = create_tcp_container("127.0.0.1", 3333)
    tr = TopologyRole()

    per_node(topology) do node
        add!(node, add_agent_composed_of(container, tr))
    end

    @test length(topology_neighbors(tr)) == 4
end

@testset "TestTopologyChooseAgent" begin
    topology = cycle_topology(4)
    container = create_tcp_container("127.0.0.1", 3333)

    choose_agent(topology) do node
        return register(container, TopologyAgent())
    end

    @test length(topology_neighbors(agents(container)[1])) == 2
    @test length(topology_neighbors(agents(container)[2])) == 2
    @test length(topology_neighbors(agents(container)[3])) == 2
    @test length(topology_neighbors(agents(container)[4])) == 2
end

@testset "TestTopologyAssignAgent" begin
    topology = cycle_topology(4)
    container = create_tcp_container("127.0.0.1", 3333)
    register(container, TopologyAgent())
    register(container, TopologyAgent())
    register(container, TopologyAgent())
    register(container, TopologyAgent())

    assign_agent(topology, container) do agent, node
        return aid(agent) == "agent" * string(node.id - 1)
    end

    @test length(topology_neighbors(agents(container)[1])) == 2
    @test length(topology_neighbors(agents(container)[2])) == 2
    @test length(topology_neighbors(agents(container)[3])) == 2
    @test length(topology_neighbors(agents(container)[4])) == 2
end

@testset "TestSetEdgeState" begin
    container = create_tcp_container("127.0.0.1", 3333)
    agent = nothing
    topology = cycle_topology(4)

    modify_topolology(topology) do topology
        agent = register(container, TopologyAgent())
        agent2 = register(container, TopologyAgent())
        agent3 = register(container, TopologyAgent())
        n1 = add_node!(topology, agent)
        n2 = add_node!(topology, agent2)
        n3 = add_node!(topology, agent3)
        add_edge!(topology, n1, n2)
        add_edge!(topology, n1, n3)
        set_edge_state!(topology, n1, n2, BROKEN)
    end

    @test topology_neighbors(agent) == [address(agents(container)[3])]
    @test topology_neighbors(agents(container)[2]) == []
    @test topology_neighbors(agents(container)[3]) == [address(agents(container)[1])]
end

@testset "TestTopologyRemoveEdgeRemoveNode" begin
    topology = complete_topology(5)
    container = create_tcp_container("127.0.0.1", 3333)

    per_node(topology) do node
        add!(node, register(container, TopologyAgent()))
    end

    modify_topolology(topology) do topology
        remove_edge!(topology, 1, 2)
        remove_node!(topology, 3)
    end

    @test length(topology_neighbors(container["agent0"])) == 2
end