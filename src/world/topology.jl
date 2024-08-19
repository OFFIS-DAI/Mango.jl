export complete_topology, star_topology, cycle_topology, graph_topology, per_node, add!, topology_neighbors, create_topology, add_node!, add_edge!, Topology

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

"""
	complete_topology(number_of_nodes)

Create a fully-connected topology.
"""
function complete_topology(number_of_nodes::Int)::Topology
    graph = complete_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

"""
	star_topology(number_of_nodes)

Create a star topology.
"""
function star_topology(number_of_nodes::Int)
    graph = star_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

"""
	cycle_topology(number_of_nodes)

Create a cycle topology.
"""
function cycle_topology(number_of_nodes::Int)
    graph = cycle_graph(number_of_nodes)
    return Topology(_create_meta_graph_with(graph))
end

"""
	graph_topology(graph)

Create a topology based on a Graphs.jl (abstract) graph.
"""
function graph_topology(graph::AbstractGraph)
    return Topology(_create_meta_graph_with(graph))
end

"""
	add_edge!(topology, node_id_from, node_id_to, directed=false)

Add an edge to the topology from `node_id_from` to `node_id_to`. If `directed` is true
a directed edge is added, otherwise an undirected edge is added.
"""
function add_edge!(topology::Topology, node_id_from::Int, node_id_to::Int, directed::Bool=false)
    if directed
        topology.graph[node_id_from, node_id_to] = nothing
    else
        topology.graph[node_id_to, node_id_from] = nothing
        topology.graph[node_id_from, node_id_to] = nothing
    end
end

"""
	add_node!(topology, agents::Agent...)::Int

Add a node to the topology with a list (or a single) of agents attached.
"""
function add_node!(topology::Topology, agents::Agent...)::Int
    vid = nv(topology.graph) + 1
    topology.graph[vid] = Node(vid, [a for a in agents])
    return vid
end

"""
	create_topology(create_runnable)::Topology

Create a topology using the `create_runnable` function which is a one-argument
function with an initially empty topology as argument.

# Example
```julia
topology = create_topology() do topology
    agent = register(container, TopologyAgent())
    agent2 = register(container, TopologyAgent())
    agent3 = register(container, TopologyAgent())
    n1 = add_node!(topology, agent)
    n2 = add_node!(topology, agent2)
    n3 = add_node!(topology, agent3)
    add_edge!(topology, n1, n2)
    add_edge!(topology, n1, n3)
end
```
"""
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

"""
	per_node(assign_runnable, topology)

Loops over the nodes of the `topology`, calls `assign_runnable` on every node to enable the caller
to populate the node. After the loop finished the neighborhoods are created and injected into the agent. 

# Example
```julia
per_node(topology) do node
    add!(node, register(container, TopologyAgent()))
end
```
"""
function per_node(assign_runnable::Function, topology::Topology)
    # 1st pass, let the user assign the agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        assign_runnable(node)
    end
    _build_neighborhoods_and_inject(topology)
end

"""
	add!(node, agent::Agent...)

Add an `agents` to the `node`.
"""
function add!(node::Node, agents::Agent...)
    for a in agents
        push!(node.agents, a)
    end
end

"""
	topology_neighbors(agent)

Retrieve the neighbors of the `agent`, represented by their addresses. These vaues will be
updated when a topology is applied using `per_node` or `create_topology`.
"""
function topology_neighbors(agent::Agent)::Vector{AgentAddress}
    return neighbors(service_of_type(agent, TopologyService, TopologyService()))
end

function topology_neighbors(role::Role)::Vector{AgentAddress}
    return neighbors(service_of_type(role.context.agent, TopologyService, TopologyService()))
end