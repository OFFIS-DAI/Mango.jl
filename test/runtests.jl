using Test

@testset "Mango Tests" begin
    include("datastructure_util_tests.jl")
    include("scheduler_tests.jl")
    include("agent_tests.jl")
    include("role_tests.jl")
    include("container_tests.jl")
    include("encode_decode_tests.jl")
    include("simulation_container_tests.jl")
    include("examples.jl")
    include("tcp_protocol_tests.jl")
    include("agent_modeling_tests.jl")
    include("express_api_tests.jl")
    include("topology_tests.jl")
end