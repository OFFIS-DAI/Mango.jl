using Test
using LightBSON

include("../src/util/encode_decode.jl")
using .EncodeDecode

import Base.==

struct MyComposite
    x::Float64
    y::String
    z::Dict{String,Int64}
end

struct MyNested
    a::MyComposite
    b::MyComposite
    c::MyComposite
    s::Union{MyNested,Nothing}
end

function ==(x::MyComposite, y::MyComposite)
    return x.x == y.x && x.y == y.y && x.z == y.z
end

function ==(x::MyNested, y::MyNested)
    return x.a == y.a && x.b == y.b && x.c == y.c && x.s == y.s
end

LightBSON.bson_simple(::Type{MyComposite}) = true
LightBSON.bson_simple(::Type{MyNested}) = true


@testset "EncodeDecode" begin
    test_string = "test"
    test_big_string = "big_string"^1
    test_floats = rand(1)
    test_dict = Dict([string(i) => i * 10 for i = 1:1])
    test_composite = MyComposite(100.0, test_big_string, test_dict)
    test_nested = MyNested(
        test_composite,
        test_composite,
        test_composite,
        MyNested(
            test_composite,
            test_composite,
            test_composite,
            MyNested(test_composite, test_composite, test_composite, nothing),
        ),
    )
    test_data =
        [test_string, test_big_string, test_floats, test_dict, test_composite, test_nested]
    test_dict = Dict([string(i) => test_data[i] for i in eachindex(test_data)])

    encoded = EncodeDecode.encode(test_dict)
    decoded = EncodeDecode.decode(encoded)

    @test true
end