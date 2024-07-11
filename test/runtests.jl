using Test

@testset "Mango Tests" begin
    include("scheduler_tests.jl")
    include("agent_tests.jl")
    include("role_tests.jl")
    include("container_tests.jl")
    include("encode_decode_tests.jl")
    include("simulation_container_tests.jl")
end