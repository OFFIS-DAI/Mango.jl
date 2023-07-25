# Not called Codecs because Codecs.jl already exists and I didn't want to deal with that for now.

#=
The result of the benchmark test was:
- JSON - simple, slow, converts structs to dicts
- CBOR - slightly faster but still slow, can reconstruct structs for you if definitions match -> convenient
- LightBSON - fast (10x faster than JSON), bit more hassle with types

Since our primary focus with Mango.jl is speed improvements over python, the primary codec is LightBSON based for now.
=#
module EncodeDecode
using LightBSON
export encode, decode, TypeAwareCodec, register_flat_type, register_deep_type

# the core functions
# these versions will reduce structs to OrderedDicts with their field names as is LightBSON default
function encode(data::Dict{String,<:Any})::Vector{UInt8}
    buf = Vector{UInt8}()
    LightBSON.bson_write(buf, data)
    return buf
end

function decode(buf::Vector{UInt8})::Dict{String,Any}
    return LightBSON.bson_read(Dict{String,Any}, buf)
end

# type extension features
mutable struct TypeAwareCodec
    known_types::Vector{Type}
    is_flat::Vector{Bool}
    encoders::Vector{Function}
    decoders::Vector{Function}

    function TypeAwareCodec()
        return new(Vector{Type}(), Vector{Bool}(), Vector{Function}(), Vector{Function}())
    end
end

function iterate_and_encode(data::Dict{String,<:Any}, codec::TypeAwareCodec)::Dict{String,Vector{UInt8}}

end

function decode_and_iterate(buf::Vector{UInt8}, codec::TypeAwareCodec)::Dict{String,Any}

end

function encode(data::Dict{String,<:Any}, codec::TypeAwareCodec)::Vector{UInt8}
    return iterate_and_encode(data, codec)
end

function decode(buf::Vector{UInt8}, codec::TypeAwareCodec)::Dict{String,Any}
    return decode_and_iterate(buf, codec)
end

function register_flat_type(codec::TypeAwareCodec, t::Type)

end

function register_flat_type(codec::TypeAwareCodec, t::Type, encoder::Function, decoder::Function)

end

function register_deep_type(codec::TypeAwareCodec, t::Type)

end

function register_deep_type(codec::TypeAwareCodec, t::Type, encoder::Function, decoder::Function)

end




end