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

@with_def struct ABC{T}
    abc::T
    i::Int = 0
end

abstract type AbstractTypeAbc end

@with_def struct ABC2 <: AbstractTypeAbc
    abc::Int
    i::Int = 0
end

@testset "TestSimpleTypeParam" begin
    abc = ABC("H")
    @test abc.abc == "H"
    @test abc.i == 0
end
@testset "TestTypeInheritanceWithDef" begin
    abc = ABC2(0)

    @test abc.abc == 0
    @test abc.i == 0
end