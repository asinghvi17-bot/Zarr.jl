# Deliberately closed schema: one full-sized raw chunk, explicit T, N and format.
# This is an executable experiment, not a replacement for general zopen/zcreate.
using ZarrCore
import JSON

function wire(::Type{Complex{T}}, shape::NTuple{N,Int}, fv::Complex{T}, ::Val{2}) where {T<:Signed,N}
    (zarr_format=2, shape=reverse(shape), chunks=reverse(shape),
     dtype=ZarrCore.typestr(Complex{T}), compressor=nothing,
     fill_value=ZarrCore.fill_value_encoding(fv), order="C", filters=nothing,
     dimension_separator=".")
end
function wire(::Type{Complex{T}}, shape::NTuple{N,Int}, fv::Complex{T}, ::Val{3}) where {T<:Signed,N}
    (zarr_format=3, node_type="array", shape=reverse(shape),
     data_type=ZarrCore.typestr3(Complex{T}),
     chunk_grid=(name="regular", configuration=(chunk_shape=reverse(shape),)),
     chunk_key_encoding=(name="default", configuration=(separator="/",)),
     fill_value=ZarrCore.fill_value_encoding3(fv),
     codecs=[(name="bytes", configuration=(endian="little",))])
end
pipeline(::Val{2}) = ZarrCore.V2Pipeline(ZarrCore.NoCompressor(), nothing)
pipeline(::Val{3}) = ZarrCore.V3Pipeline((), ZarrCore.BytesCodec(:little), ())
metakey(::Val{2}) = ".zarray"
metakey(::Val{3}) = "zarr.json"
chunkkey(::Val{2}, ::Val{N}) where N = join(ntuple(_ -> "0", Val(N)), ".")
chunkkey(::Val{3}, ::Val{N}) where N = "c/" * join(ntuple(_ -> "0", Val(N)), "/")

function writearray(path::String, data::Array{Complex{T},N}, version::Val;
                    fill_value::Complex{T}=zero(Complex{T})) where {T<:Signed,N}
    N > 0 && all(>(0), size(data)) || throw(ArgumentError("Expected a nonempty array of positive rank"))
    mkpath(path)
    md = wire(Complex{T}, size(data), fill_value, version)
    write(joinpath(path, metakey(version)), JSON.json(md))
    if version isa Val{2}
        write(joinpath(path, ".zattrs"), "{}")
    end
    # Use the production codec kernels; no codec name lookup or mutable registry.
    bytes = ZarrCore.pipeline_encode(pipeline(version), data, nothing)::Vector{UInt8}
    chunk = joinpath(path, chunkkey(version, Val(N)))
    mkpath(dirname(chunk))
    write(chunk, bytes)
    return nothing
end

function validate(md, ::Type{C}, ::Val{2}) where C
    md.zarr_format == 2 && md.chunks == md.shape && md.order == "C" &&
        md.dimension_separator == "." && md.dtype == ZarrCore.typestr(C) ||
        throw(ArgumentError("Expected one raw little-endian C-order v2 chunk"))
    ZarrCore.typestr(md.dtype, C)
    return ZarrCore.fill_value_decoding(md.fill_value, C)
end
function validate(md, ::Type{C}, ::Val{3}) where C
    md.zarr_format == 3 && md.node_type == "array" &&
        md.chunk_grid.name == "regular" && md.chunk_grid.configuration.chunk_shape == md.shape &&
        md.chunk_key_encoding.name == "default" && md.chunk_key_encoding.configuration.separator == "/" &&
        length(md.codecs) == 1 && md.codecs[1].name == "bytes" &&
        md.codecs[1].configuration.endian == "little" ||
        throw(ArgumentError("Expected one raw little-endian v3 chunk"))
    ZarrCore.typestr3(md.data_type, C)
    return ZarrCore.fill_value_decoding(md.fill_value, C)
end

function readarray(::Type{Complex{T}}, path::String, version::Val, ::Val{N}) where {T<:Signed,N}
    N > 0 || throw(ArgumentError("Expected positive rank"))
    C = Complex{T}
    # The expected wire schema is compiled in; data values and sizes are runtime inputs.
    template = wire(C, ntuple(_ -> 1, Val(N)), zero(C), version)
    md = JSON.parse(read(joinpath(path, metakey(version)), String), typeof(template))
    fv = validate(md, C, version)
    all(>(0), md.shape) || throw(ArgumentError("Expected nonempty dimensions"))
    output = fill(fv, reverse(md.shape))
    chunk = joinpath(path, chunkkey(version, Val(N)))
    if isfile(chunk)
        bytes = read(chunk)
        length(bytes) == sizeof(output) || throw(ArgumentError("Incorrect chunk size"))
        ZarrCore.pipeline_decode!(pipeline(version), output, bytes)
    end
    return output
end
