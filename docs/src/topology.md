# Topologies

In Mango.jl agents usually communicate with each other based on a topology. The topology determines which agent can communicate with which agent. To implement this, every agent has access to a so-called neighborhood, which is the set of all agents it can communicate to. 

As it can be pretty clunky to create every neighborhood-list manually, Mango.jl provides several functions to make your life easier. For this it relys on `Graphs.jl` and `MetaGraphsNext.jl` as datastructure and for graph-construction

# Creating topologies

First, there are several pre-defined topologies. It is also possible to use an arbitrary Graphs.jl graph. After the creation of the topology, the agents need to be added to the topology. This can be done with `per_node(topology) do node ... end`. In the do-block it is possible to add agents to nodes, the do-block will be executed per vertex of your graph. 

```julia
topology = complete_topology() # fully connected 
topology = star_topology() # star
topology = cycle_topology() # cycle
topology = graph_topology(your_graph) # based on arbitrary Graphs.jl AbstractGraph
per_node(topology) do node
    add!(node, MyAgent())
end
```

However, often this approach is not feasible, because you create a specific agent system with agents which need to be linked in a very specific way, such that it is not possible to assign the same agent type to every node. For this reason you can define the topology manually:

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

# Using the topology

At this point we know how to create topologies and how to populate them. To actually use them, the function `topology_neighbors(agent_or_role)` exists. The function returns a vector of AgentAddress objects, which represent all other agents in the neighborhood of `agent`.