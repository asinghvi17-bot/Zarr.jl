@testset "Concrete complex integer metadata" begin
    for T in (Int8, Int16, Int32, Int64)
        C = Complex{T}
        d2 = ZarrCore.typestr(C)
        d3 = ZarrCore.typestr3(C)
        @test d2 isa Vector{Vector{String}}
        @test d3 isa NamedTuple
        @test ZarrCore.typestr(d2, C) === C
        @test ZarrCore.typestr3(d3, C) === C
        other = T === Int8 ? Complex{Int16} : Complex{Int8}
        @test_throws ArgumentError ZarrCore.typestr(d2, other)
        @test_throws ArgumentError ZarrCore.typestr3(d3, other)
        fv = C(7, -8)
        @test ZarrCore.fill_value_decoding(ZarrCore.fill_value_encoding3(fv), C) === fv
        for version in (2, 3)
            mktempdir() do path
                data = reshape(C.(1:12, -12:-1), 3, 4)
                z = zcreate(C, 3, 4; path, chunks=(2, 3), zarr_format=version,
                            fill_value=fv, compressor=Zarr.NoCompressor())
                z[:, 1:3] = data[:, 1:3]
                reopened = zopen(path)
                @test reopened[:, 1:3] == data[:, 1:3]
                @test all(==(fv), reopened[:, 4])
                @test isconcretetype(fieldtype(typeof(z.metadata), :dtype))
                @test isconcretetype(fieldtype(typeof(reopened.metadata), :dtype))
                @test ZarrCore.Metadata(json(z.metadata), false) == z.metadata
            end
        end
    end
    # Keep the stored byte-order marker instead of regenerating the v2 dtype.
    d = JSON.parse(json(ZarrCore.Metadata(Complex{Int16}[1-2im], (1,))); dicttype=Dict{String,Any})
    d["dtype"] = [["r", ">i2"], ["i", ">i2"]]
    md = ZarrCore.Metadata(d, false)
    @test JSON.parse(json(md))["dtype"] == d["dtype"]
    @test_throws ArgumentError ZarrCore.typestr([["r", "<i16"], ["i", "<i16"]])
    @test_throws ArgumentError ZarrCore.typestr(Complex{Int128})
    @test_throws ArgumentError ZarrCore.typestr3(Complex{Int128})
end


@testset "Complex integer Base64 wire compatibility" begin
    for T in (Int8, Int16, Int32, Int64)
        for r in (typemin(T), typemax(T), zero(T), one(T), -one(T)),
            i in (typemin(T), typemax(T), zero(T), one(T), -one(T))
            value = Complex{T}(r, i)
            expected = ZarrCore.base64encode(reinterpret(UInt8, T[htol(r), htol(i)]))
            @test ZarrCore.fill_value_encoding(value) == expected
            @test ZarrCore.fill_value_decoding(expected, Complex{T}) === value
        end
    end
    for malformed in ("", "AQD+/w=", "AQD+/w===", "!!!!/w==", "AQD+/x==", "AQD+/w=A")
        @test_throws ArgumentError ZarrCore.fill_value_decoding(malformed, Complex{Int16})
    end
end
