include("array.jl")

function roundtrip(::Type{T}, path::String, version::Val, seed::Int) where {T<:Signed}
    C = Complex{T}
    data = reshape(C[C(seed, -2), C(3, -4), C(-5, 6), C(7, -8)], 2, 2)
    writearray(path, data, version; fill_value=C(9, -10))
    output = readarray(C, path, version, Val(2))
    output == data || return false
    # Verify missing-chunk semantics too.
    rm(joinpath(path, chunkkey(version, Val(2))))
    all(==(C(9, -10)), readarray(C, path, version, Val(2))) || return false
    writearray(path, data, version; fill_value=C(9, -10))
    return true
end

function (@main)(args)::Cint
    length(args) == 2 || return 2
    root, seed = args[1], parse(Int, args[2])
    for version in (Val(2), Val(3))
        v = version isa Val{2} ? "v2" : "v3"
        roundtrip(Int8, joinpath(root, v * "-int8"), version, seed) || return 1
        roundtrip(Int16, joinpath(root, v * "-int16"), version, seed) || return 1
        roundtrip(Int32, joinpath(root, v * "-int32"), version, seed) || return 1
        roundtrip(Int64, joinpath(root, v * "-int64"), version, seed) || return 1
    end
    return 0
end
