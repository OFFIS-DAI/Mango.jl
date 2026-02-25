using Test
using Documenter

@testset "Mango Tests" begin
    include("system_programming_tests.jl")
    include("datastructure_util_tests.jl")
    include("scheduler_tests.jl")
    include("agent_tests.jl")
    include("role_tests.jl")
    include("container_tests.jl")
    include("encode_decode_tests.jl")
    include("world_tests.jl")
    include("examples.jl")
    include("tcp_protocol_tests.jl")
    include("agent_modeling_tests.jl")
    include("express_api_tests.jl")
    include("topology_tests.jl")
    include("environment_api_tests.jl")
    include("recording_and_position_tests.jl")
    include("simulation_convenience_api_tests.jl")
    if get(ENV, "MANGO_TEST_VISUALIZATION", "false") == "true"
        include("visualization_tests.jl")
    end
    doctest(Mango)
end