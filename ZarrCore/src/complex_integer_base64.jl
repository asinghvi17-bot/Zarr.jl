# Small RFC 4648 codec for the fixed-size v2 complex-integer fill records.
# Base64's streaming pipes have abstract IO fields (even for IOBuffer), so
# calling base64encode/base64decode pulls unresolved IO calls into --trim.
const _RECORD_BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function encode_complex_fill(v::Complex{T}) where {T<:Signed}
    # The dtype we emit is little endian, independently of the host byte order.
    bytes = reinterpret(UInt8, T[htol(real(v)), htol(imag(v))])
    n = length(bytes)
    output = fill(UInt8('='), 4 * cld(n, 3))
    alphabet = codeunits(_RECORD_BASE64_ALPHABET)
    j = 1
    for i in 1:3:n
        a = bytes[i]
        b = i + 1 <= n ? bytes[i + 1] : 0x00
        c = i + 2 <= n ? bytes[i + 2] : 0x00
        output[j] = alphabet[Int(a >> 2) + 1]
        output[j + 1] = alphabet[Int(((a & 0x03) << 4) | (b >> 4)) + 1]
        i + 1 <= n && (output[j + 2] = alphabet[Int(((b & 0x0f) << 2) | (c >> 6)) + 1])
        i + 2 <= n && (output[j + 3] = alphabet[Int(c & 0x3f) + 1])
        j += 4
    end
    return String(output)
end

function record_base64_digit(c::UInt8)
    UInt8('A') <= c <= UInt8('Z') && return c - UInt8('A')
    UInt8('a') <= c <= UInt8('z') && return c - UInt8('a') + 0x1a
    UInt8('0') <= c <= UInt8('9') && return c - UInt8('0') + 0x34
    c == UInt8('+') && return 0x3e
    c == UInt8('/') && return 0x3f
    throw(ArgumentError("Invalid Base64 complex integer fill value"))
end

function decode_complex_fill(s::AbstractString, ::Type{Complex{T}}) where {T<:Signed}
    n = 2 * sizeof(T)
    input = codeunits(s)
    length(input) == 4 * cld(n, 3) ||
        throw(ArgumentError("Incorrect Base64 complex integer fill value length"))
    bytes = Vector{UInt8}(undef, n)
    j = 1
    for i in 1:4:length(input)
        a, b = record_base64_digit(input[i]), record_base64_digit(input[i + 1])
        bytes[j] = (a << 2) | (b >> 4)
        if j + 1 <= n
            c = record_base64_digit(input[i + 2])
            bytes[j + 1] = (b << 4) | (c >> 2)
            if j + 2 <= n
                d = record_base64_digit(input[i + 3])
                bytes[j + 2] = (c << 6) | d
            else
                input[i + 3] == UInt8('=') && (c & 0x03) == 0 ||
                    throw(ArgumentError("Invalid Base64 fill value padding"))
            end
        else
            input[i + 2] == input[i + 3] == UInt8('=') && (b & 0x0f) == 0 ||
                throw(ArgumentError("Invalid Base64 fill value padding"))
        end
        j += 3
    end
    values = reinterpret(T, bytes)
    return Complex{T}(ltoh(values[1]), ltoh(values[2]))
end
