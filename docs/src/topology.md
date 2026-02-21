# Topology

In Mango.jl, a **topology** defines which agents can communicate with which other agents. Instead of maintaining address lists manually, agents use a topology service to discover their neighbors at runtime. Topologies are built on `Graphs.jl` and `MetaGraphsNext.jl`.

---

## Creating a Topology

### Pre-built graph shapes

```@example topo_create
using Mango, Graphs

@agent struct TopoAgent end

topology = star_topology(5)      # one hub connected to 4 leaves
topology = cycle_topology(4)     # ring
topology = complete_topology(3)  # all-to-all (fully connected)
topology = graph_topology(complete_digraph(3))  # from any Graphs.jl graph

topology.graph  # the underlying MetaGraph
```

### Assigning agents to nodes

After creating the graph shape, assign agents to nodes. The assignment determines which agent "lives" at which node and therefore who each agent's neighbors are.

```julia
world = create_world(DateTime(0))
agents_list = [register(world, TopoAgent()) for _ in 1:3]

# Automatically distribute agents round-robin across all nodes
topo = complete_topology(3)
auto_assign!(topo, world)
```

Other assignment functions:

| Function | Description |
|---|---|
| [`auto_assign!`](@ref) | Round-robin assignment to a container or world |
| [`assign_agents!`](@ref) | Assign a provided list of agents in order |
| [`choose_agents!`](@ref) | Use a selection function to pick agents per node |
| [`per_node`](@ref) | Map from node index to agent for manual assignment |

### Manual topology creation

For precise control over the graph structure and agent placement:

```@example topo_manual
using Mango

@agent struct ManualAgent end
container = Container()

topology = create_topology() do t
    a0 = register(container, ManualAgent())
    a1 = register(container, ManualAgent())
    a2 = register(container, ManualAgent())

    n0 = add_node!(t, a0)
    n1 = add_node!(t, a1)
    n2 = add_node!(t, a2)

    add_edge!(t, n0, n1)
    add_edge!(t, n0, n2)
    # a1 and a2 can reach a0, but not each other
end
```

Use [`modify_topology`](@ref) to add or remove nodes and edges after creation.

---

## Inspecting a Topology

Mango.jl extends `Graphs.jl` functions so they work directly on `Topology` objects:

```julia
using Graphs, Mango
t = complete_topology(5)

nv(t)                  # number of vertices: 5
ne(t)                  # number of edges: 10
vertices(t)            # [1, 2, 3, 4, 5]
edges(t)               # edge iterator
has_edge(t, 1, 2)      # true
inneighbors(t, 2)      # [1, 3, 4, 5]
outneighbors(t, 2)     # [1, 3, 4, 5]
is_directed(t)         # false
```

---

## Using the Topology at Runtime

### Discover neighbors

`topology_neighbors` returns the addresses of all agents reachable from a given agent within their topology:

```julia
neighbors = topology_neighbors(agent)
for addr in neighbors
    send_message(agent, "hello", addr)
end
```

Optional keyword arguments let you filter the result:

| Keyword | Default | Description |
|---|---|---|
| `tid` | `:default` | Topology ID (for agents in multiple topologies) |
| `state` | `NORMAL` | Only include edges with this state |
| `has_characteristic` | `[]` | Only neighbors with all listed characteristics |
| `include_connectors` | `[]` | Also include connector agents for these types |
| `match_func` | `_ -> true` | Custom filter on neighbor `AgentDescription` |

`topology_neighbors` is also available on roles:

```julia
topology_neighbors(role)
```

---

## Edge States

Edges between agents can be in one of five states, modelling link health:

| State | Meaning |
|---|---|
| `NORMAL` | Active, included in neighbor queries by default |
| `INACTIVE` | Disabled, excluded from default queries |
| `BROKEN` | Failed link |
| `UNKNOWN` | State not yet determined |
| `EXT_CONNECTION` | External (cross-topology) connection |

Change an edge state:

```julia
set_edge_state!(topology, node_a, node_b, BROKEN)
```

Query only neighbors reachable via `INACTIVE` edges:

```julia
topology_neighbors(agent; state=INACTIVE)
```

---

## Agent Characteristics

Nodes in a topology can carry arbitrary symbolic characteristics (e.g. `:leader`, `:gateway`). This lets agents filter neighbors by role or capability:

```julia
set_characteristic!(topology, node_id, :gateway)

# Only neighbors tagged as :gateway
topology_neighbors(agent; has_characteristic=:gateway)
```

---

## Connecting Multiple Topologies

For large systems it is often cleaner to define several smaller topologies and then connect them. The connection points are called **connectors**.

### Mark an agent as a connector

```julia
mark_as_connector!(agent)                      # default connection type :default
mark_as_connector!(agent, :backbone)           # named connection type
```

### Connect two topologies

```julia
topology_a = complete_topology(3)
topology_b = complete_topology(3)

auto_assign!(topology_a, world)
auto_assign!(topology_b, world)

# Link all :default connectors of A with all :default connectors of B
connect_topologies!(topology_a, topology_b)

# Directed: A's connectors see B's connectors, but not vice versa
connect_topologies!(topology_a, topology_b; directed=true)
```

After connecting, use `include_connectors` to make cross-topology neighbors visible:

```julia
# Includes neighbors reachable via :default connector links
topology_neighbors(agent; include_connectors=[:default])
```

### Full multi-topology example

```julia
world = create_world(DateTime(0))
agents1 = [register(world, TopoAgent()) for _ in 1:3]
agents2 = [register(world, TopoAgent()) for _ in 1:3]

mark_as_connector!(agents1[1])
mark_as_connector!(agents2[1])

topo1 = complete_topology(3)
topo2 = complete_topology(3)
auto_assign!(topo1, world)
auto_assign!(topo2, world)

connect_topologies!(topo1, topo2)

# agents1[1] can now reach agents2[1] via the connector link
topology_neighbors(agents1[1]; include_connectors=[:default])
```

---

## Topology ID

When an agent belongs to more than one topology, each topology is given a unique `tid::Symbol`. Pass `tid=:my_topology` to `topology_neighbors` (and related functions) to select which topology to query. The default is `:default`.
