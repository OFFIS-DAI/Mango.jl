# Topologies

In Mango.jl agents usually communicate with each other based on a topology. The topology determines which agent can communicate with which agent. To implement this, every agent has access to a neighborhood, which is the set of all agents it can communicate with. 

As it can be pretty clunky to create every neighborhood-list manually, Mango.jl provides several functions to make your life easier. For this it relys on `Graphs.jl` and `MetaGraphsNext.jl` as datastructure and for graph-construction

# Creating topologies

There are two ways to create a working topology:
1. You choose a graph and an assignment mechanism. 
2. You create the whole topology and do the assignment of the agents to each node manualy.

## Graph + Assignment Mechanism

To start creating a topology you can use several pre-defined topologies. It is also possible to use an arbitrary Graphs.jl graph.

```@example
using Mango, Graphs

@agent struct MyAgent end

topology = star_topology(3) # star
topology = cycle_topology(3) # cycle
topology = complete_topology(3) # fully connected 
topology = graph_topology(complete_digraph(3)) # based on arbitrary Graphs.jl AbstractGraph

# resulting topology graph
topology.graph
```

After the topology is instantiated the agents need to be assigned in way that suits your goal of communication structure between the agents. Mango.jl provides some eays-to-use functions for that: [`per_node`](@ref), [`auto_assign!`](@ref), [`assign_agents!`](@ref), [`choose_agents!`](@ref).

## Manual Creation

However, sometimes it is easier to manually define everything, because you create a specific agent system with agents which need to be linked in a very specific way. For this reason you can define the topology manually:

```@example
using Mango 

@agent struct TopologyAgent end
container = Container()

topology = create_topology() do topology
    agent0 = register(container, TopologyAgent())
    agent1 = register(container, TopologyAgent())
    agent2 = register(container, TopologyAgent())
    n1 = add_node!(topology, agent0)
    n2 = add_node!(topology, agent1)
    n3 = add_node!(topology, agent2)
    add_edge!(topology, n1, n2)
    add_edge!(topology, n1, n3)
end

# neighbors of `agent`
topology_neighbors(container[1])
```

If you need to modify a topology manually you can use [`modify_topology`](@ref).


# Inspecting topologies

Functions that are defined on `Graphs.jl`graphs have been extended with methods for topologies so the following calls will resolve normally. 
Note that this requires `using Graphs` as well as `using Mango` to resolve correctly:
```julia
using Graphs, Mango
topology = complete_topology(5)

edges(topology) # SimpleEdgeIter 10
edgetype(topology) # Graphs.SimpleGraphs.SimpleEdge{Int64}
has_edge(topology, 1, 2) # true
has_vertex(topology, 1) # true
inneighbors(topology, 2) # [1, 3, 4, 5]
outneighbors(topology, 2) # [1, 3, 4, 5]
is_directed(topology) # false
ne(topology) # 10
nv(topology) # 5
vertices(topology) # [1, 2, 3, 4, 5]
```

# Using the topology

At this point we know how to create topologies and how to populate them. To actually use them, the function [`topology_neighbors`](@ref) exists. The function returns a vector of AgentAddress objects, which represent all other agents in the neighborhood of `agent`.

# Connecting topologies together

Sometimes systems become so complex that creating multiple simple topologies is easier than creating one complex topology. If you use more than only one topology, you can connect your topologies together to be linked on so-called `connectors`.

`Connectors` are single agents, which act as connection points between topologies. A connector can accept specific `connection types`. A connection type is a `Symbol` (e.g. :default), which specifies the type of connection a connector can establish. To mark an agent as connector you can use [`mark_as_connector!`](@ref).

If you connect two topologies, say topology A and topology B, using a specific connection type c, all connectors of A and B will be linked if they are connectors for the connection type c. Imagine there is one connector in A and one in B that are defined for the same connection type. This would result in an extended neighborhood for the connector in A, which now includes the connector from B and vice versa. To access the extended neighborhood you can use the `include
