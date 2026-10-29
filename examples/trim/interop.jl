# Run with --project=Zarr/test after disk-smoke has written trimmed-fixtures.
using Test, Zarr
root = joinpath(@__DIR__, "trimmed-fixtures")
@testset "Trim executable stores opened by Zarr" begin
    for version in (2, 3), T in (Int8, Int16, Int32, Int64)
        C = Complex{T}
        path = joinpath(root, "v$version-int$(8sizeof(T))")
        z = zopen(path)
        @test z[:, :] == reshape(C[C(23, -2), C(3, -4), C(-5, 6), C(7, -8)], 2, 2)
        @test eltype(z) === C
    end
end
# Produce independent stores through Zarr's public API for the typed reader.
for version in (2, 3), T in (Int8, Int16, Int32, Int64)
    C = Complex{T}
    path = joinpath(@__DIR__, "zarr-fixtures", "v$version-int$(8sizeof(T))")
    z = zcreate(C, 2, 2; path, chunks=(2, 2), zarr_format=version,
                compressor=Zarr.NoCompressor(), fill_value=C(9, -10))
    z[:, :] = reshape(C[C(23, -2), C(3, -4), C(-5, 6), C(7, -8)], 2, 2)
end
