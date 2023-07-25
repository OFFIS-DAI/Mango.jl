using Test
using LightBSON
using OrderedCollections

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
    test_dict = OrderedDict(
        [
        ("1" => 1.0),
        ("2" => "two"),
        ("3" => 10)
    ]
    )

    encoded = EncodeDecode.encode(test_dict)
    decoded = EncodeDecode.decode(encoded)

    @test test_dict == decoded
end