export complete_topology, star_topology, cycle_topology, graph_topology, per_node, add!,
    topology_neighbors, create_topology, add_node!, add_edge!, Topology, modify_topology,
    choose_agents!, assign_agents!, NORMAL, BROKEN, INACTIVE, set_edge_state!, remove_edge!, remove_node!,
    auto_assign!, topology_node_id, topology_to_aid_graph, set_as_connector!, connect_topologies!, mark_as_connector!,
    topology_connectors, topology_connection_types, NORMAL, INACTIVE, BROKEN, UNKNOWN, EXT_CONNECTION, State, topology_service,
    set_characteristic!, topology_characteristic

using MetaGraphsNext
using Graphs
import Graphs.add_edge!

@kwdef struct Node
    id::Int
    agents::Vector{Agent} = Vector()
    characteristics::Dict{Agent,Symbol} = Dict() # special agents having specific roles, e.g. :lead for coalition leaders
end

struct TopologyNeighbor
    address::AgentAddress
    description::AgentDescription
    characteristic::Symbol

    function TopologyNeighbor(address::AgentAddress, description::AgentDescription, characteristic::Symbol=:nothing)
        new(address, description, characteristic)
    end
end

@kwdef struct Topology
    tid::Symbol
    graph::MetaGraph
    connectors::Vector{Tuple{Symbol,TopologyNeighbor}} = Vector() # connection type to connector
    connections::Vector{Tuple{Symbol,Topology}} = Vector() # tid to connection type
end

function set_characteristic!(topology::Topology, nid::Int64, agent::Agent, characteristic::Symbol)
    node = topology.graph[nid]
    node.characteristics[agent] = characteristic
end

@enum State begin
    NORMAL # normal neighbor
    INACTIVE # neighbor link exists but link is not active (could be activated/used)
    BROKEN # neighbor link exists but link is not usable (can not be activated)
    UNKNOWN # = nothing
    EXT_CONNECTION # external connection
end

@kwdef mutable struct TopologyService
    tid_to_state_to_neighbors::Dict{Symbol,Dict{State,Vector{TopologyNeighbor}}} = Dict() # tid to (edge state to agents)
    tid_to_connectors::Dict{Symbol,Vector{Tuple{Symbol, TopologyNeighbor}}} = Dict() # tid to (connection type to connected agents)
    tid_to_node_id::Dict{Symbol,Int} = Dict() # tid to id of the node
    marked_connector_for::Vector{Symbol} = Vector()
    tid_to_characteristic::Dict{Symbol,Symbol} = Dict()
end

function service_node_id(service::TopologyService, tid::Symbol=:default)
    if !haskey(service.tid_to_node_id, tid)
        throw(ArgumentError("Tid $tid is unknown!"))
    end
    return service.tid_to_node_id[tid]
end

function _has_characteristic(characteristic::Symbol, has_characteristic::Union{Symbol,Vector{Symbol}})
    # no characteristic was demanded or the characteristic is included in the demanded ones
    return characteristic == has_characteristic || isa(has_characteristic, Vector) && 
        (length(has_characteristic) == 0 || characteristic ∈ has_characteristic)
end

function neighbors(service::TopologyService, tid::Symbol=:default, state::State=NORMAL; has_characteristic::Union{Symbol,Vector{Symbol}}=Vector{Symbol}(), include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)
    if haskey(service.tid_to_state_to_neighbors, tid)
        return vcat([n.address for n in get(service.tid_to_state_to_neighbors[tid], state, Vector()) if _has_characteristic(n.characteristic, has_characteristic) && match_func(n.description)], 
                    [t[2].address for t in service.tid_to_connectors[tid] if t[1] in include_connectors && match_func(t.description)])
    end
    throw(ArgumentError("No neighbors found for tid=$tid"))
end 

function connectors(service::TopologyService, tid::Symbol=:default; include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)
    if haskey(service.tid_to_state_to_neighbors, tid)
        return [t[2].address for t in service.tid_to_connectors[tid] if (t[1] in include_connectors || length(include_connectors) == 0) && match_func(t)]
    end
    throw(ArgumentError("No neighbors found for tid=$tid"))
end

function connection_types(service::TopologyService, tid::Symbol=:default)
    if haskey(service.tid_to_state_to_neighbors, tid)
        return [t[1] for t in service.tid_to_connectors[tid]]
    end
    throw(ArgumentError("No neighbors found for tid=$tid"))
end

function characteristic(service::TopologyService, tid::Symbol=:default)
    if haskey(service.tid_to_characteristic, tid)
        return service.tid_to_characteristic[tid]
    end
    return :nothing
end

function _create_meta_graph_with(graph::AbstractGraph)
    vertices_description = [i => Node(id=i) for i in vertices(graph)]
    edges_description = [(e.src, e.dst) => NORMAL for e in edges(graph)]

    return MetaGraph(graph, vertices_description, edges_description)
end

"""
	complete_topology(number_of_nodes)

Create a fully-connected topology.
"""
function complete_topology(number_of_nodes::Int; tid::Symbol=:default)::Topology
    graph = complete_graph(number_of_nodes)
    return Topology(tid=tid, graph=_create_meta_graph_with(graph))
end

"""
	star_topology(number_of_nodes)

Create a star topology.
"""
function star_topology(number_of_nodes::Int; tid::Symbol=:default)
    graph = star_graph(number_of_nodes)
    return Topology(tid=tid, graph=_create_meta_graph_with(graph))
end

"""
	cycle_topology(number_of_nodes)

Create a cycle topology.
"""
function cycle_topology(number_of_nodes::Int; tid::Symbol=:default)
    graph = cycle_graph(number_of_nodes)
    return Topology(tid=tid, graph=_create_meta_graph_with(graph))
end

"""
	graph_topology(graph)

Create a topology based on a Graphs.jl (abstract) graph.
"""
function graph_topology(graph::AbstractGraph; tid::Symbol=:default)
    return Topology(tid=tid, graph=_create_meta_graph_with(graph))
end

"""
	add_edge!(topology, node_id_from, node_id_to, directed=false)

Add an edge to the topology from `node_id_from` to `node_id_to`. If `directed` is true
a directed edge is added, otherwise an undirected edge is added.
"""
function add_edge!(topology::Topology, node_id_from::Int, node_id_to::Int, state::State=NORMAL; directed::Bool=false)
    if directed
        topology.graph[node_id_from, node_id_to] = state
    else
        topology.graph[node_id_to, node_id_from] = state
        topology.graph[node_id_from, node_id_to] = state
    end
end

"""
    remove_edge!(topology::Topology, node_id_from::Int, node_id_to::Int)

Remove the edge between `node_id_from` and `node_id_to`.
"""
function remove_edge!(topology::Topology, node_id_from::Int, node_id_to::Int)
    return rem_edge!(topology.graph, node_id_from, node_id_to)
end

"""
    remove_node!(topology::Topology, node_id::Int)

Remove the node with the id `node_id`.
"""
function remove_node!(topology::Topology, node_id::Int)
    return rem_vertex!(topology.graph, node_id)
end

"""
	add_node!(topology, agents::Agent...)::Int

Add a node to the topology with a list (or a single) of agents attached.
"""
function add_node!(topology::Topology, agents::Agent...; id::Union{Int,Nothing}=nothing)::Int
    vid = isnothing(id) ? nv(topology.graph) + 1 : id
    topology.graph[vid] = Node(id=vid, agents=[a for a in agents])
    return vid
end

"""
    set_as_connectors!(topology::Topology, agents..., connector_type::Symbol=:default)

Set `agents` as connectors (has to be part of the topology)
"""
function set_as_connector!(topology::Topology, agents...; connector_type::Symbol=:default)
    for a in agents
        push!(topology.connectors, (connector_type, TopologyNeighbor(address(a), description(a))))
    end
end

function mark_as_connector!(agent::Agent, connector_type::Symbol=:default)
    ts = service_of_type(agent, TopologyService, TopologyService())
    push!(ts.marked_connector_for, connector_type)
end

"""
    connect(topology_one::Topology, topology_two::Topology, connection_type::Symbol; directed::Bool=false)

Connect two topologies on all connectors identified by connection_type.
"""
function connect_topologies!(topology_one::Topology, topology_two::Topology, connection_type::Symbol=:default; directed::Bool=false)
    if directed
        push!(topology_one.connections, (connection_type, topology_two))
        _build_neighborhoods_and_inject(topology_one)
    else
        push!(topology_two.connections, (connection_type, topology_one))
        push!(topology_one.connections, (connection_type, topology_two))
        _build_neighborhoods_and_inject(topology_one)
        _build_neighborhoods_and_inject(topology_two)
    end
end

"""
    set_state!(topology::Topology, node_id_from::Int, node_id_to::Int, state::State)

Set the state of the state of the edge `(node_id_from, node_id_to)` to `state`.
"""
function set_edge_state!(topology::Topology, node_id_from::Int, node_id_to::Int, state::State, include_other_direction=true)
    topology.graph[node_id_from, node_id_to] = state
    if include_other_direction
        if has_edge(topology.graph, node_id_to, node_id_from)
            topology.graph[node_id_to, node_id_from] = state
        end
    end
end

function _build_connectors_list_for(topology, agent)
    connectors_for_agent = []
    for (type, other_topo) in topology.connections
        # check whether agent is a connector for the connection
        for (c_type, neighbor) in topology.connectors
            if type == c_type && uid(agent) == neighbor.description.uid
                # it is a connector
                # now find the fitting connectors in the connected topo
                for (other_c_type, other_neighbor) in other_topo.connectors
                    if type == other_c_type
                        push!(connectors_for_agent, (type, other_neighbor))
                    end
                end
            end
        end
    end
    return connectors_for_agent
end

function _characteristic_for(node::Node, agent::Agent)
    return get!(node.characteristics, agent, :nothing)
end

function _build_neighborhoods_and_inject(topology::Topology; build_connected=true)
    # 2nd pass, build the neighborhoods and add it to agents
    for label in labels(topology.graph)
        node = topology.graph[label]
        state_to_neighbors::Dict{State,Vector{TopologyNeighbor}} = Dict{State,Vector{TopologyNeighbor}}()
        for n_label in neighbor_labels(topology.graph, label)
            n_node = topology.graph[n_label]
            state = topology.graph[node.id, n_node.id]
            neighbor_addresses = get!(state_to_neighbors, state, Vector())
            append!(neighbor_addresses, [TopologyNeighbor(address(agent), description(agent), _characteristic_for(n_node, agent)) for agent in n_node.agents])
        end
        for agent in node.agents
            # also include agents from your own node (not you!)
            state_to_same = deepcopy(state_to_neighbors)
            for other_agent in node.agents
                if aid(agent) != aid(other_agent)
                    neighbors = get!(state_to_same, NORMAL, Vector())
                    push!(neighbors, TopologyNeighbor(address(other_agent), description(other_agent), _characteristic_for(node, other_agent)))
                end
            end
            topology_service = service_of_type(agent, TopologyService, TopologyService())
            topology_service.tid_to_state_to_neighbors[topology.tid] = state_to_same
            topology_service.tid_to_node_id[topology.tid] = node.id
            topology_service.tid_to_characteristic[topology.tid] = _characteristic_for(node, agent)

            # look for marks and transfer to topology 
            for type in topology_service.marked_connector_for
                if (type, description(agent)) ∉ [(c[1], c[2].description) for c in topology.connectors]
                    push!(topology.connectors, (type, TopologyNeighbor(address(agent), description(agent))))
                end
            end
            # search for connection agents
            connectors_for_agent = _build_connectors_list_for(topology, agent)
            topology_service.tid_to_connectors[topology.tid] = connectors_for_agent
        end
    end
    if build_connected
        for (_, topo) in topology.connections
            _build_neighborhoods_and_inject(topo, build_connected=false)
        end
    end
end

"""
    create_topology(create_runnable::Function; tid::Symbol=:default, directed::Bool=false)

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
function create_topology(create_runnable::Function; tid::Symbol=:default, directed::Bool=false)
    topology = Topology(tid=tid, graph=_create_meta_graph_with(directed ? DiGraph() : Graph()))
    create_runnable(topology)
    _build_neighborhoods_and_inject(topology)
    return topology
end

"""
    modify_topology(modify_runnable::Functino, topology::Topology)

Modify a topology using the `modify_runnable` function which is a one-argument
function with the provided topology as argument.

# Example
```julia
modify_topology(my_topology) do topology
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
function modify_topology(modify_runnable::Function, topology::Topology)
    modify_runnable(topology)
    _build_neighborhoods_and_inject(topology)
    return topology
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
    return topology
end


function auto_assign!(topology::Topology, agents)
    index_to_label = collect(labels(topology.graph))
    for (i, agent) in enumerate(agents)
        label = index_to_label[(((i-1)%length(index_to_label))+1)]
        node = topology.graph[label]
        add!(node, agent)
    end
    _build_neighborhoods_and_inject(topology)
    return topology
end

"""
    auto_assign(topology, container)

Assign all agents of the `container` to the nodes of the `topology`. The agents are assigned
to the nodes in the order of the nodes in the graph.
"""
function auto_assign!(topology::Topology, container::ContainerInterface)
    return auto_assign!(topology::Topology, agents(container))
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
    assign_agent(assign_condition::Function, topology::Topology, container::ContainerInterface)

Assign all agents of the `container` to the nodes based on the given `assign_condition`, this condition 
takes as `Agent` and a `Node` (node.id for the identifier of the node) and shall return a boolean indicating
whether the agent shall be assigned to the node.
"""
function assign_agents!(assign_condition::Function, topology::Topology, container::ContainerInterface)
    per_node(topology) do node
        for agent in agents(container)
            if assign_condition(agent, node)
                add!(node, agent)
            end
        end
    end
end

"""
    choose_agent(choose_agent_function::Function, topology::Topology)

Choose the agents, which shall be assigned to the nodes. For this the `choose_agent_function` has to be provided. This 
function expects `Node` as argument and shall return an `Agent` or `Agent...`. The returned agent will be assigned to the node.
"""
function choose_agents!(choose_agent_function::Function, topology::Topology)
    per_node(topology) do node
        agent = choose_agent_function(node)
        add!(node, agent)
    end
end

"""
    topology_neighbors(agent::Agent; tid::Symbol=:default, state::State=NORMAL)::Vector{AgentAddress}

Retrieve the neighbors of the `agent`, represented by their addresses. These vaues will be
updated when a topology is applied using `per_node` or `create_topology`.
"""
function topology_neighbors(agent::Agent; tid::Symbol=:default, state::State=NORMAL, has_characteristic::Union{Symbol,Vector{Symbol}}=Vector{Symbol}(), include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)::Vector{AgentAddress}
    return neighbors(service_of_type(agent, TopologyService, TopologyService()), tid, state, has_characteristic=has_characteristic, include_connectors=include_connectors, match_func=match_func)
end

function topology_neighbors(role::Role; tid::Symbol=:default, state::State=NORMAL, has_characteristic::Union{Symbol,Vector{Symbol}}=Vector{Symbol}(), include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)::Vector{AgentAddress}
    return neighbors(service_of_type(role.context.agent, TopologyService, TopologyService()), tid, state, has_characteristic=has_characteristic, include_connectors=include_connectors, match_func=match_func)
end

function topology_service(role::Role)
    return service_of_type(role.context.agent, TopologyService, TopologyService())
end

"""
    topology_node_id(agent::Agent; tid::Symbol=:default)::Int

Retrieve the node id the `agent` is assigned to.
"""
function topology_node_id(agent::Agent; tid::Symbol=:default)::Int
    return service_node_id(service_of_type(agent, TopologyService, TopologyService()), tid)
end

function topology_node_id(role::Role; tid::Symbol=:default)::Int
    return service_node_id(service_of_type(role.context.agent, TopologyService, TopologyService()), tid)
end

"""
    topology_connectors(agent::Agent; tid::Symbol=:default, state::State=NORMAL, include_connectors::Vector{Symbol}=Vector{Symbol}())::Vector{AgentAddress}

Retrieve the connectors of the `agent`, represented by their addresses. These vaues will be
updated when a topology is applied using `per_node` or `create_topology`.
"""
function topology_connectors(agent::Agent; tid::Symbol=:default, include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)::Vector{AgentAddress}
    return connectors(service_of_type(agent, TopologyService, TopologyService()), tid, include_connectors=include_connectors, match_func=match_func)
end

function topology_connectors(role::Role; tid::Symbol=:default, include_connectors::Vector{Symbol}=Vector{Symbol}(), match_func::Function=(desc)->true)::Vector{AgentAddress}
    return connectors(service_of_type(role.context.agent, TopologyService, TopologyService()), tid, include_connectors=include_connectors, match_func=match_func)
end


"""
    topology_connection_types(agent::Agent; tid::Symbol=:default, include_connectors::Vector{Symbol}=Vector{Symbol}())::Vector{AgentAddress}

Retrieve the connection_types for connectors used available to the `agent`, represented by their addresses. These vaues will be
updated when a topology is applied using `per_node` or `create_topology`.
"""
function topology_connection_types(agent::Agent; tid::Symbol=:default)::Vector{Symbol}
    return connection_types(service_of_type(agent, TopologyService, TopologyService()), tid)
end

function topology_connection_types(role::Role; tid::Symbol=:default)::Vector{Symbol}
    return connection_types(service_of_type(role.context.agent, TopologyService, TopologyService()), tid)
end

function topology_characteristic(agent::Agent; tid::Symbol=:default)::Symbol
    return characteristic(service_of_type(agent, TopologyService, TopologyService()), tid)
end

function topology_characteristic(role::Role; tid::Symbol=:default)::Symbol
    return characteristic(service_of_type(role.context.agent, TopologyService, TopologyService()), tid)
end


# Graphs API calls forwarded to Topology
function Graphs.edges(topology::Topology)
    return edges(topology.graph)
end

function Graphs.edgetype(topology::Topology)
    return edgetype(topology.graph)
end

function Graphs.vertices(topology::Topology)
    return vertices(topology.graph)
end

function Graphs.has_edge(topology::Topology, s::Any, d::Any)
    return has_edge(topology.graph, s, d)
end

function Graphs.has_vertex(topology::Topology, v::Any)
    return has_vertex(topology.graph, v)
end

function Graphs.inneighbors(topology::Topology, v::Any)
    return inneighbors(topology.graph, v)
end

function Graphs.outneighbors(topology::Topology, v::Any)
    return outneighbors(topology.graph, v)
end

function Graphs.is_directed(topology::Topology)
    return is_directed(topology.graph)
end

function Graphs.ne(topology::Topology)
    return ne(topology.graph)
end

function Graphs.nv(topology::Topology)
    return nv(topology.graph)
end

"""
    topology_to_aid_graph(topology::Topology)::AbstractGraph

Convert the topology graph to an aid based graph, where every node is representing exactly one agent.
"""
function topology_to_aid_graph(topology::Topology)
    vertex_description::Vector{Pair{String,Agent}} = []
    edges_description::Vector{Pair{Tuple{String,String},State}} = []
    graph = SimpleGraph()
    aid_to_vertex = Dict()
    for vertex in vertices(topology.graph)
        label = label_for(topology.graph, vertex)
        node = topology.graph[label]
        for agent in node.agents
            add_vertex!(graph)
            push!(vertex_description, aid(agent) => agent)
            aid_to_vertex[aid(agent)] = nv(graph)
        end
        for agent in node.agents
            for agent_two in node.agents
                if agent == agent_two
                    continue
                end
                if !has_edge(graph, aid_to_vertex[aid(agent)], aid_to_vertex[aid(agent_two)])
                    add_edge!(graph, aid_to_vertex[aid(agent)], aid_to_vertex[aid(agent_two)])
                    push!(edges_description, (aid(agent), aid(agent_two)) => NORMAL)
                end
            end
        end
    end
    for edge in edges(topology.graph)
        edge_src_code = edge.src
        edge_dst_code = edge.dst
        edge_src_label = label_for(topology.graph, edge_src_code)
        edge_dst_label = label_for(topology.graph, edge_dst_code)
        edge_src_node = topology.graph[edge_src_label]
        edge_dst_node = topology.graph[edge_dst_label]
        for agent_src in edge_src_node.agents
            for agent_dst in edge_dst_node.agents
                if !has_edge(graph, aid_to_vertex[aid(agent_src)], aid_to_vertex[aid(agent_dst)])
                    add_edge!(graph, aid_to_vertex[aid(agent_src)], aid_to_vertex[aid(agent_dst)])
                    push!(edges_description, (aid(agent_src), aid(agent_dst)) => topology.graph[edge_src_label, edge_dst_label])
                end
            end
        end
    end
    return MetaGraph(graph, vertex_description, edges_description)
end
