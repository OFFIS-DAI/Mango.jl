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
using OrderedCollections
export encode, decode, TypeAwareCodec, register_flat_type, register_deep_type

# the core functions
# these versions will reduce structs to OrderedDicts with their field names as is LightBSON default
function encode(data::Union{Dict{String,<:Any},OrderedDict{String,<:Any}})::Vector{UInt8}
    buf = Vector{UInt8}()
    LightBSON.bson_write(buf, data)
    return buf
end

function decode(buf::Vector{UInt8})::OrderedDict{String,Any}
    return LightBSON.bson_read(OrderedDict{String,Any}, buf)
end


end