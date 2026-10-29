include("array.jl")
function (@main)(args)::Cint
    length(args) == 1 || return 2
    for version in (Val(2), Val(3))
        v = version isa Val{2} ? "v2" : "v3"
        check_interop(Int8, args[1], v, version) || return 1
        check_interop(Int16, args[1], v, version) || return 1
        check_interop(Int32, args[1], v, version) || return 1
        check_interop(Int64, args[1], v, version) || return 1
    end
    return 0
end
function check_interop(::Type{T}, root::String, v::String, version::Val) where {T<:Signed}
    C = Complex{T}
    path = joinpath(root, v * "-int$(8sizeof(T))")
    expected = reshape(C[C(23, -2), C(3, -4), C(-5, 6), C(7, -8)], 2, 2)
    readarray(C, path, version, Val(2)) == expected
end
