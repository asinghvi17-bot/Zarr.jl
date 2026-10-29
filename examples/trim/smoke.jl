using ZarrCore

function exercise(::Type{T}) where {T<:Signed}
    C = Complex{T}
    d2 = ZarrCore.typestr(C)
    d3 = ZarrCore.typestr3(C)
    ZarrCore.typestr(d2, C) === C || return false
    ZarrCore.typestr3(d3, C) === C || return false
    fv = C(1, -2)
    ZarrCore.fill_value_decoding(ZarrCore.fill_value_encoding(fv), C) == fv || return false
    ZarrCore.fill_value_decoding(ZarrCore.fill_value_encoding3(fv), C) == fv || return false
    data = C[C(1, -2), C(3, -4)]
    p2 = ZarrCore.V2Pipeline(ZarrCore.NoCompressor(), nothing)
    p3 = ZarrCore.V3Pipeline((), ZarrCore.BytesCodec(:little), ())
    for p in (p2, p3)
        bytes = ZarrCore.pipeline_encode(p, data, nothing)::Vector{UInt8}
        output = similar(data)
        ZarrCore.pipeline_decode!(p, output, bytes)
        output == data || return false
    end
    return true
end

function (@main)(args)::Cint
    exercise(Int8) && exercise(Int16) && exercise(Int32) && exercise(Int64) ? 0 : 1
end
