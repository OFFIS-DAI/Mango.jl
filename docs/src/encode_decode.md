# Codecs

A **codec** is a pair of `(encode, decode)` functions that Mango.jl applies to messages at the container boundary — serializing before sending over the network and deserializing after receiving. Codecs are only active for real-time containers (TCP, MQTT); simulation containers operate in-process and do not serialize messages.

---

## When Codecs Are Used

| Context | Codec applied? |
|---|---|
| TCP container (cross-process) | Yes |
| MQTT container (cross-process) | Yes |
| Simulation `World` (in-process) | No |
| Same-container local delivery | No |

The default codec uses [LightBSON.jl](https://github.com/ancapdev/LightBSON.jl) for BSON serialization and is set automatically when you call `create_tcp_container` or `create_mqtt_container`.

---

## Default Codec: BSON

`encode` serializes an `OrderedDict{String, Any}` to a `Vector{UInt8}` BSON buffer. `decode` converts it back:

```@example
using Mango
using OrderedCollections

msg = OrderedDict{String,Any}("type" => "ping", "count" => 3)

encoded = encode(msg)
decoded = decode(encoded)

decoded["type"]   # "ping"
decoded["count"]  # 3
```

For full information on which Julia types round-trip through BSON see the [LightBSON.jl documentation](https://github.com/ancapdev/LightBSON.jl).

!!! note "Type information is not preserved"
    The current codec does not embed type metadata. Numeric types may be widened on round-trip (e.g. `Int32` may come back as `Int64`). Use `OrderedDict{String, Any}` as the canonical message format and handle type coercion in your `handle_message` if needed.

---

## Setting a Custom Codec

Pass a `(encode, decode)` tuple to the container factory:

```julia
my_encode(data) = Vector{UInt8}(JSON.json(data))
my_decode(bytes) = JSON.parse(String(bytes))

container = create_tcp_container("127.0.0.1", 5555; codec=(my_encode, my_decode))
```

Both functions must satisfy:
- `encode(data)::Vector{UInt8}` — data is an `OrderedDict{String, Any}`
- `decode(bytes::Vector{UInt8})::OrderedDict{String, Any}`

---

## Disabling the Codec

Set `codec=nothing` to disable serialization entirely. This is useful when both containers run in the same process and you want to pass raw Julia objects:

```julia
container = create_tcp_container("127.0.0.1", 5555; codec=nothing)
```

!!! warning "Not suitable for cross-process communication"
    Without a codec, message objects are transmitted as raw bytes using Julia's default serialization, which is version-dependent and not portable. Only disable the codec when both endpoints are in the same Julia session.
