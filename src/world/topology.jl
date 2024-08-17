export complete_topology, star_topology, cycle_topology, graph_topology, per_node, add!, topology_neighbors

using MetaGraphsNext
using Graphs

@kwdef struct Node
    id::Int
    agents::Vector{Agent} = Vector()
end

struct Topology
    graph::MetaGraph
end

@kwdef mutable struct TopologyService
    neighbors::Vector{AgentAddress} = Vector()
end

function neighbors(service::TopologyService)
    return service.neighbors
end

function _create_meta_graph_with(graph::Graph)
    vertices_description = [i => Node(i) for i in vertices(graph)]
    edges_description = [
        (e.src, e.dst) => nothing for e in edges(graph)
    ]

    return MetaGraph(graph, vertices_description, edges_description)
end

function complete_topology(number_of_nodes::Int)
    complete_graph = complete_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(complete_graph))
end

function star_topology(number_of_nodes::Int)
    complete_graph = star_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(complete_graph))
end

function cycle_topology(number_of_nodes::Int)
    complete_graph = cycle_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(complete_graph))
end

function graph_topology(graph::Graph)
    return Topology(_create_meta_graph_with(graph))
end

function per_node(assign_runnable::Function, topology::Topology)
    # 1st pass, let the user assign the agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        assign_runnable(node)
    end
    # 2nd pass, build the neighborhoods and add it to agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        neighbor_addresses = Vector()
        for n_label in neighbor_labels(topology.graph, label)
            n_node = topology.graph[n_label]
            push!(neighbor_addresses, [address(node) for agent in n_node.agents])
        end
        for agent in node.agents
            topology_service = service_of_type(agent, TopologyService, TopologyService())
            topology_service.neighbors = neighbor_addresses
        end
    end
end

function add!(node::Node, agent::Agent)
    push!(node.agents, agent)
end

function topology_neighbors(agent::Agent)::Vector{AgentAddress}
    return neighbors(service_of_type(agent, TopologyService, TopologyService()))
end