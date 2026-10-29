# Complex integer arrays and Julia trimming

The goals of [JuliaIO/Zarr.jl#361](https://github.com/JuliaIO/Zarr.jl/pull/361)
can be met in a statically selected implementation. The PR's general metadata
discovery path is not trim-friendly. Merely replacing `Vector{Any}` with a type
parameter is insufficient. This branch is a prototype based on PR head
`0293226dd8f902593e9bc481fe0500a45926788e`, not a claim that all of Zarr now trims.

## What the PR does

NumPy has no complex-integer primitive dtype. The PR represents
`Complex{Int8/Int16/Int32/Int64}` as two signed integer fields, `r` and `i`:

- v2: `[["r", "<i2"], ["i", "<i2"]]` for Int16, and Base64 bytes for the fill.
- v3: the `struct` extension with named field objects and an object fill
  `{"r": 1, "i": -2}`. It also reads the older `structured`/pair-fields form.

It changes metadata type discovery, serialization and fill handling. It does
not introduce a new data codec: Julia's isbits complex layout already has the
two consecutive integer components needed by the existing raw/bytes codecs.
Its tests cover v2/v3 round trips and Python fixtures.

The review asks whether the `Any` containers are necessary, whether the dtype
field should be concrete, and whether this follows the struct extension. The
PR author explains that the stored dtype preserves wire details such as byte
order, and offers either a union or an additional dtype parameter. Anshul's
[latest comment](https://github.com/JuliaIO/Zarr.jl/pull/361#discussion_r4415448401)
asks for an alternative to `Any`.

## Actual obstacles

| Location at PR head | Why it matters |
| --- | --- |
| `metadata.jl`, `typestr(fields)` | Indexes nested `Any` values, retrieves a `DataType` from the mutable `typemap`, and constructs `Complex{T}` from that runtime type. |
| `metadata3.jl`, `typestr3`/`parse_datatype3` | Creates `Dict{String,Any}` trees, extracts fields dynamically, obtains `T` from mutable `typemap3::Dict{String,DataType}`, and constructs `Complex{T}`. The result is not a statically selected element type. |
| `metadata.jl`, `fill_value_encoding`/`fill_value_decoding` | New Base64 calls reach stdlib `Base64EncodePipe.io::IO` and `Base64DecodePipe.io::IO`. These abstract fields cause unresolved `write`, `unsafe_write`, `eof`, and decoding calls even with an actual IOBuffer. |
| Existing generic `Metadata`/`zopen` path | Parses JSON into `Dict{String,Any}` and constructs rank, format, element type, filters and codecs from runtime values. A concrete dtype field does not fix this discovery boundary. |
| Existing compressor and codec registries | `compressortypes` stores abstract compressor types; `codec_parsers` stores `CodecEntry` with abstract `return_type::Type{<:V3Codec}` and `parser::Function`. Registry-selected constructors/parsers cannot be statically resolved in general. |
| Existing `ZArray.attrs::Dict` and heterogeneous pipeline loops | These remain potential dynamic paths. In particular, collecting heterogeneous codec tuples into vectors in `pipeline_decode!` loses concrete element types. They are not necessary to implement the new complex dtype. |

No feature-time `eval` or `invokelatest` was introduced by #361. Module loading
and facade reexports are distinct from runtime metadata/codec discovery.
A small union field is not inherently a trim failure, nor does an `Any`
container necessarily contaminate a kernel that never reads it. The failures
above were observed on exercised paths, rather than inferred from spelling.

## Prototype

1. Add a dtype parameter `D` to v2 and v3 metadata, retaining the old partially
   parameterized constructors. Preserve v2 wire strings, including endian
   markers. Normalize v2 structured fields into `Vector{Vector{String}}`.
2. Represent generated v3 dtype/configuration/field/fill objects with concrete
   named tuples. Normalize complex v3 metadata to this representation after
   parsing. The emitted JSON is unchanged.
3. Resolve the four supported signed widths with explicit branches returning
   literal types. Provide `typestr(dtype, Complex{T})` and
   `typestr3(dtype, Complex{T})` validators for a statically selected type.
   Reject unsupported components (including Int128) rather than emit a dtype
   that the closed reader cannot read.
4. Use a small RFC 4648 byte codec for the fixed-size v2 fill record. It avoids
   the Base64 streaming pipes and explicitly encodes little-endian components.
   Boundary-value tests compare its output with Julia's Base64 implementation.
5. `array.jl` demonstrates typed JSON parsing (`JSON.parse(text, WireType)`),
   direct construction of concrete production pipelines, actual filesystem
   metadata and chunk I/O, and typed reading with missing-chunk fills. No
   runtime codec registry is consulted.

The example deliberately supports one full-sized raw chunk, positive rank and
nonempty dimensions, little endian, v2 C order or v3 regular/default/bytes,
and an explicitly selected element type, rank and format. It handles arbitrary
runtime sizes and data within that schema. This is an executable experiment,
not a general replacement for `zopen`/`zcreate`. Extending it to multiple chunks
and statically supplied compressor pipelines is possible, but not proven here.
The production JIT API still handles chunked/compressed arrays and legacy v3
metadata; the restricted trimmed reader accepts the canonical current struct
form. General plugin discovery still needs a finite compiled set of choices
or a separate dynamic/JIT boundary.

API trade-offs: fully specifying `ZArray{...,MetadataV2{T,N,C,F}}` inside the
invariant outer type is no longer an exact match; use
`ZArray{...,<:MetadataV2{T,N,C,F}}`. Metadata receives an additional trailing
parameter. Generated v3 objects/fills are named tuples instead of dictionaries.
The fixed-record Base64 reader accepts canonical padded Base64; unlike the
stdlib streaming decoder it does not ignore whitespace or arbitrary characters.
JSON 0.21 compatibility was not tested. No claim is made about big-endian
hosts or compressed trim executables.

## Reproduce

Run from the repository root with Julia 1.13.2 and JuliaC 0.3.12. The example
requires JSON 1.12 or later; Zarr itself retains its existing JSON compatibility.
`--compiled-modules=existing` avoids unrelated initial stdlib cache rebuilds in
this worker; it does not suppress trim verification. Neither `--trim=unsafe`
nor `--trim=no` is used.

```sh
julia --project=examples/trim -e 'using Pkg; Pkg.instantiate()'
julia --compiled-modules=existing --project=examples/trim -m JuliaC \
  --experimental --trim --output-exe disk-smoke examples/trim/disk_smoke.jl
./disk-smoke examples/trim/trimmed-fixtures 23

# Read the executable's stores with the regular Zarr API, then create independent stores.
julia --project=Zarr/test -e 'using Pkg; Pkg.instantiate()'
julia --compiled-modules=existing --project=Zarr/test examples/trim/interop.jl
julia --compiled-modules=existing --project=examples/trim -m JuliaC \
  --experimental --trim --output-exe read-interop examples/trim/read_interop.jl
./read-interop examples/trim/zarr-fixtures
python3 examples/trim/check_wire.py examples/trim/trimmed-fixtures

# The full repository suite, followed by the explicitly limited native runner.
julia --compiled-modules=existing --project=Zarr/test Zarr/test/runtests.jl
julia --compiled-modules=existing --project=Zarr/test examples/trim/run_native_tests.jl
```

To reproduce the negative baseline, check out PR head in a separate worktree,
copy the example Project/Manifest to a temporary environment, and change its
ZarrCore path source to that worktree's ZarrCore. Run JuliaC with that
environment as `--project` and `baseline_smoke.jl` as its source. Do not point
it at this branch's ZarrCore. The recorded baseline had 68 verifier errors;
its first error is the unresolved `fill_value_decoding` call with a
`Type{Complex{_A}} where _A` obtained from `parse_datatype3`.

## Evidence

Observed: both plain-`--trim` builds and executable runs succeeded; the final
native suite passed **1197/1197** tests, including **278** new feature assertions.
Zarr read the eight executable-generated stores in **16/16** assertions, and the
trimmed reader read eight Zarr-created stores. See `evidence/` for verifier
excerpts and final test/build results. Both
executables exercise runtime inputs; their checks return a nonzero status on
failure. `disk-smoke` tests all four widths and both versions, writes and reads
2x2 arrays and metadata, checks absent chunk fill behavior, then rewrites the
chunks for independent readers. `read-interop` reads arrays created by Zarr.

The unrestricted suite was run and failed on missing MinIO service and
micromamba lazy artifact setup. The initial run also exposed two type identity
assertions affected by the new metadata parameter; those assertions were
updated. The native runner changes only its in-memory test source to omit
MinIO, `python.jl`, and Python/fixture-dependent portions of `consolidated.jl`,
leaving repository tests intact and retaining the remaining consolidated tests. The v3 Python fixture
checks follow the suite's existing skip behavior when fixture directories are
absent. Python cross-language interoperability was not independently verified
in this worker.
