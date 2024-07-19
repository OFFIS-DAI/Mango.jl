using Mango
using Test
using ConcurrentCollections

@testset "TestLengthConcurrentQueue" begin
    queue = ConcurrentQueue()
    push!(queue, 1)
    push!(queue, 2)
    push!(queue, 3)

    @test length(queue) == 3
end