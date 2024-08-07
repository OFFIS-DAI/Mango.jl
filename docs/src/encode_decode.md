# Mango.jl Encoding and Decoding (codec) Feature User Documentation

Codecs provide functions for serializing and deserializing data to Mango containers.
They use [LightBSON.jl](https://github.com/ancapdev/LightBSON.jl) as their backend.


As of now, the `encode` and `decode` functions forward their inputs directly to `bson_read` and `bson_write`.
For most cases, we expect to pass messages as `OrderedDict{String, Any}`.
We also forward an optional type field when decoding that is passed to `bson_write` to make use of the existing type-casting functionality here.
For full information on what will work with this type of inference, we refer to the LightBSON.jl documentation.

For future versions, we plan on adding a more convenient (but likely slower) type inference variant of the codec that saves necessary type information when encoding and iterates the output data while decoding to restore it exactly as it was before encoding (including type information).
