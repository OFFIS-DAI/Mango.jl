using Test
using LightBSON
using OrderedCollections

include("../src/util/encode_decode.jl")
using .EncodeDecode

import Base.==

struct MyComposite
    x::Float64
    y::String
    z::OrderedDict{String,Any}
end

function ==(x::MyComposite, y::MyComposite)
    return x.x == y.x && x.y == y.y && x.z == y.z
end

LightBSON.bson_simple(::Type{MyComposite}) = true
LightBSON.bson_simple(::Type{MyNested}) = true


@testset "EncodeDecode" begin
    #= things that will not pass the simple equality check:
        - imaginary numbers (get cast to ordered dicts with "re" and "im" keys)
        - nested structures
        - anything self referential
    =#
    test_dict1 = OrderedDict(
        [
        "1" => 1.0,
        "2" => "two",
        "3" => 1,
        "4" => [1, 2, 3, 5, 6, 7],
        "5" => [1.0, 2.0, Inf, NaN],
        "6" => ["a", "b", "c", "d"],
        "7" => Any["a", 1.0, NaN, Inf, zeros(Float64, 10)],
        "8" => Any[OrderedDict{String,Any}(["a" => "nested"])]
    ]
    )

    test_dict2 = OrderedDict{String,Any}()

    encoded = EncodeDecode.encode(test_dict1)
    decoded = EncodeDecode.decode(encoded)
    @test isequal(decoded, test_dict1)

    encoded = EncodeDecode.encode(test_dict2)
    decoded = EncodeDecode.decode(encoded)
    @test isequal(decoded, test_dict2)

    composite = MyComposite(10.0, "some string", OrderedDict(["abc" => 123, "def" => 456]))
    encoded = EncodeDecode.encode(composite)
    decoded = EncodeDecode.decode(encoded, MyComposite)
    @test isequal(decoded, composite)
end