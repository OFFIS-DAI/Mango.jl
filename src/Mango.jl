"""
Placeholder for a short summary about mango.
"""
module Mango

include("util/scheduling.jl")
include("util/encode_decode.jl")
include("container/api.jl")

include("agent/api.jl")
include("agent/role.jl")
include("agent/core.jl")

include("container/protocol.jl")
include("container/tcp.jl")
include("simulation/communication.jl")
include("simulation/tasks.jl")
include("container/simulation.jl")
include("container/core.jl")

end # module
