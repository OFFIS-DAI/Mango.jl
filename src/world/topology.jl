export complete_topology, star_topology, cycle_topology, graph_topology, per_node, add!, topology_neighbors, create_topology, add_node!, add_edge!

using MetaGraphsNext
using Graphs
import Graphs.add_edge!

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

function _create_meta_graph_with(graph::AbstractGraph)
    vertices_description = [i => Node(id=i) for i in vertices(graph)]
    edges_description = [
        (e.src, e.dst) => nothing for e in edges(graph)
    ]

    return MetaGraph(graph, vertices_description, edges_description)
end

function complete_topology(number_of_nodes::Int)
    graph = complete_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

function star_topology(number_of_nodes::Int)
    graph = star_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

function cycle_topology(number_of_nodes::Int)
    graph = cycle_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

function graph_topology(graph::Graph)
    return Topology(_create_meta_graph_with(graph))
end

function add_edge!(topology::Topology, node_id_from::Int, node_id_to::Int, directed=false)
    if directed
        topology.graph[node_id_from, node_id_to] = nothing
    else
        topology.graph[node_id_to, node_id_from] = nothing
        topology.graph[node_id_from, node_id_to] = nothing
    end
end

function add_node!(topology::Topology, agents::Agent...)::Int
    vid = nv(topology.graph) + 1
    topology.graph[vid] = Node(vid, [a for a in agents])
    return vid
end

function create_topology(create_runnable::Function)
    topology = Topology(_create_meta_graph_with(DiGraph()))
    create_runnable(topology)
    _build_neighborhoods_and_inject(topology)
    return topology
end

function _build_neighborhoods_and_inject(topology::Topology)
    # 2nd pass, build the neighborhoods and add it to agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        neighbor_addresses::Vector{AgentAddress} = Vector{AgentAddress}()
        for n_label in neighbor_labels(topology.graph, label)
            n_node = topology.graph[n_label]
            append!(neighbor_addresses, [address(agent) for agent in n_node.agents])
        end
        for agent in node.agents
            topology_service = service_of_type(agent, TopologyService, TopologyService())
            topology_service.neighbors = neighbor_addresses
        end
    end
end

function per_node(assign_runnable::Function, topology::Topology)
    # 1st pass, let the user assign the agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        assign_runnable(node)
    end
    _build_neighborhoods_and_inject(topology)
end

function add!(node::Node, agent::Agent...)
    for a in agent
        push!(node.agents, a)
    end
end

function topology_neighbors(agent::Agent)::Vector{AgentAddress}
    return neighbors(service_of_type(agent, TopologyService, TopologyService()))
end

function topology_neighbors(role::Role)::Vector{AgentAddress}
    return neighbors(service_of_type(role.context.agent, TopologyService, TopologyService()))
end