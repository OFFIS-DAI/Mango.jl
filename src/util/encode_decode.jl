export encode, decode

using LightBSON
using OrderedCollections

"""
    encode(data::OrderedDict{String,Any})

Encode `data` into a UInt8 buffer using LightBSON.


# Examples
```julia-repl
julia> data = OrderedDict(["test" => 10])
OrderedDict{String, Int64} with 1 entry:
  "test" => 10

julia> encode(data)
19-element Vector{UInt8}:
 0x13
 0x00
 0x00
 0x00
 0x12
    ⋮
 0x00
 0x00
 0x00
 0x00
 0x00
```
"""
function encode(data::Any)::Vector{UInt8}
    buf = Vector{UInt8}()
    LightBSON.bson_write(buf, data)
    return buf
end

function encode(data::OrderedDict{String,Any})::Vector{UInt8}
    buf = Vector{UInt8}()
    LightBSON.bson_write(buf, data)
    return buf
end

"""
    decode(buf::Vector{UInt8}, t::Type=OrderedDict{String, Any})

Decode the data in `buf` into an object of type `t` using `LightBSON.bson_read`.

# Examples
```julia-repl
julia> data = OrderedDict(["test" => 10])
OrderedDict{String, Int64} with 1 entry:
  "test" => 10

julia> decode(encode(data))
OrderedDict{String, Any} with 1 entry:
  "test" => 10
```
"""
function decode(
    buf::Vector{UInt8},
    t::Type=OrderedDict{String,Any},
)::Union{OrderedDict{String,Any},Any}
    return LightBSON.bson_read(t, buf)
end