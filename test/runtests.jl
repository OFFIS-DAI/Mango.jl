using Test

@testset "Mango Tests" begin
    include("agent_tests.jl")
    include("container_tests.jl")
end