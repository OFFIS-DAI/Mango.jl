# API

# Express

This part contains basic convenience functions for creating and running Mango.jl simulations. 

```@autodocs
Modules = [Mango]
Private = false
Pages = ["express/api.jl"]
```

# Agent and Roles

Here, the API for the agent structs created with @agent/@role is listed. 

```@autodocs
Modules = [Mango]
Private = false
Pages = ["agent/api.jl", "agent/core.jl", "agent/role.jl", "agent/services.jl"]
Order = [:macro, :function, :constant, :type, :module]
```

# Real time container

This part contains the API related to the container construction, access and management.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["container/api.jl", "container/core.jl", "container/mqtt.jl", "container/protocol.jl", "container/tcp.jl"]
```

# Simulation

In the following the APIs regarding the simulation world are listed.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["simulation/container.jl", "simulation/communication.jl", "simulation/tasks.jl", "simulation/world.jl"]
```

# Simulation Environment

In the following the APIs regarding the simulation environment are listed.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["environment/api.jl", "environment/core.jl"]
```

# Scheduling

In the following the APIs for scheduling TaskData is listed.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["util/scheduling.jl"]
```

# Topology

In the following the APIs for creating, aplying and using topologies is listed.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["util/topology.jl"]
```

# Encoding/Decoding

In the following the built-in functions for encoding and decoding messages are listed.

```@autodocs
Modules = [Mango]
Private = false
Pages = ["util/encode_decode.jl"]
```

# Misc


```@autodocs
Modules = [Mango]
Private = false
Pages = ["util/datastructures_util.jl"]
```