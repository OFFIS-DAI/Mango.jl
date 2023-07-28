using Test

@testset "Mango Tests" begin
    include("scheduler_tests.jl")
    include("agent_tests.jl")
    include("container_tests.jl")
end