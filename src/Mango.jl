"""
Placeholder for a short summary about mango.
"""
module Mango

include("util/error_handling.jl")
include("util/datastructures_util.jl")
include("util/scheduling.jl")
include("util/encode_decode.jl")
include("agent/api.jl")
include("container/api.jl")

include("agent/role.jl")
include("agent/core.jl")
include("world/core.jl")

include("container/protocol.jl")
include("container/tcp.jl")
include("container/mqtt.jl")

include("simulation/communication.jl")
include("simulation/tasks.jl")
include("container/simulation.jl")
include("container/core.jl")

include("world/topology.jl")

include("express/api.jl")

end # module
