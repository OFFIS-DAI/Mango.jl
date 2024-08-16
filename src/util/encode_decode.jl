export encode, decode

using LightBSON
using OrderedCollections

struct MsgContent
    typeinfo::String
    payload::Vector{UInt8}
end

#= 
These versions will reduce structs to OrderedDicts with their field names as is LightBSON default.
"Normal" operation is passing OrderedDict with String keys and basic data type fields.

For convenience, we pass the type info to the bson_read function so you CAN pass structs to and from
the codec and get your desired type inference.
This is entirely limited by what bson_read will handle for the types and we make no guarantees on
the results.

Advanced features like nested smart type inference and such are kept as future work.
=#
function encode(data::Union{OrderedDict{String,Any},Any})::Vector{UInt8}
    buf = Vector{UInt8}()
    LightBSON.bson_write(buf, data)
    return buf
end

function decode(
    buf::Vector{UInt8},
    t::Type = OrderedDict{String,Any},
)::Union{OrderedDict{String,Any},Any}
    return LightBSON.bson_read(t, buf)
end