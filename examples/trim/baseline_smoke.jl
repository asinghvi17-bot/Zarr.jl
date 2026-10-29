# Compile against the unmodified #361 head to demonstrate the automatic
# metadata-to-element-type boundary. The registry lookup cannot be resolved.
using ZarrCore
function (@main)(args)::Cint
    length(args) == 1 || return 2
    n = parse(Int16, args[1])
    dtype = ZarrCore.typestr3(Complex{Int16})
    T = ZarrCore.typestr3(dtype)
    value = ZarrCore.fill_value_decoding(Dict("r" => n, "i" => Int16(-2)), T)
    return real(value) == n && imag(value) == -2 ? 0 : 1
end
