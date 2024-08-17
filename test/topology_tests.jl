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

    @test topology_neighbors(agents(container)[1]) == [AgentAddress()]
end