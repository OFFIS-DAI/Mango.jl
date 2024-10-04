# Topologies

In Mango.jl agents usually communicate with each other based on a topology. The topology determines which agent can communicate with which agent. To implement this, every agent has access to a neighborhood, which is the set of all agents it can communicate with. 

As it can be pretty clunky to create every neighborhood-list manually, Mango.jl provides several functions to make your life easier. For this it relys on `Graphs.jl` and `MetaGraphsNext.jl` as datastructure and for graph-construction

# Creating topologies

First, there are several pre-defined topologies. It is also possible to use an arbitrary Graphs.jl graph. After the creation of the topology, the agents need to be added to the topology. This can be done with `per_node(topology) do node ... end`. In the do-block it is possible to add agents to nodes, the do-block will be executed per vertex of your graph. 

```@example
using Mango, Graphs

@agent struct MyAgent end

topology = star_topology(3) # star
topology = cycle_topology(3) # cycle
topology = complete_topology(3) # fully connected 
topology = graph_topology(complete_digraph(3)) # based on arbitrary Graphs.jl AbstractGraph

per_node(topology) do node
    add!(node, MyAgent())
end

# resulting topology graph
topology.graph
```

However, often this approach is not feasible, because you create a specific agent system with agents which need to be linked in a very specific way, such that it is not possible to assign the same agent type to every node. For this reason you can define the topology manually:

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
