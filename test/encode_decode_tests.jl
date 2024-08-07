using Test
using LightBSON
using OrderedCollections
using Sockets: InetAddr

include("../src/util/encode_decode.jl")

import Base.==

struct MangoMessage
    content::Any
    meta::Dict{String,Any}
end

function ==(x::MangoMessage, y::MangoMessage)
    return x.content == y.content && x.meta == y.meta
end

struct MyComposite
    x::Float64
    y::String
    z::OrderedDict{String,Any}
end

function ==(x::MyComposite, y::MyComposite)
    return x.x == y.x && x.y == y.y && x.z == y.z
end

@testset "EncodeDecode" begin
    #= things that will not pass the simple equality check:
        - imaginary numbers (get cast to ordered dicts with "re" and "im" keys)
        - nested structures
        - anything self referential
    =#
    test_dict1 = OrderedDict([
        "1" => 1.0,
        "2" => "two",
        "3" => 1,
        "4" => [1, 2, 3, 5, 6, 7],
        "5" => [1.0, 2.0, Inf, NaN],
        "6" => ["a", "b", "c", "d"],
        "7" => Any["a", 1.0, NaN, Inf, zeros(Float64, 10)],
        "8" => Any[OrderedDict{String,Any}(["a" => "nested"])],
    ])

    test_dict2 = OrderedDict{String,Any}()

    encoded = encode(test_dict1)
    decoded = decode(encoded)
    @test isequal(decoded, test_dict1)

    encoded = encode(test_dict2)
    decoded = decode(encoded)
    @test isequal(decoded, test_dict2)

    composite = MyComposite(10.0, "some string", OrderedDict(["abc" => 123, "def" => 456]))
    encoded = encode(composite)
    decoded = decode(encoded, MyComposite)
    @test isequal(decoded, composite)

    mango_msg = MangoMessage(
        "some_message",
        Dict(["test" => 123, "blubb" => "bla", "addr" => InetAddr(ip"127.0.0.2", 2981)]),
    )

    expected_output = MangoMessage(
        "some_message",
        Dict(["test" => 123, "blubb" => "bla", "addr" => "127.0.0.2:2981"]),
    )

    encoded = encode(mango_msg)
    decoded = decode(encoded, MangoMessage)
    @test isequal(decoded, expected_output)
end