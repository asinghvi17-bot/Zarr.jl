# Run the repository suite, omitting only unavailable external-service tests.
using Test
root = normpath(joinpath(@__DIR__, "../.."))
testfile = joinpath(root, "Zarr/test/runtests.jl")
source = read(testfile, String)
storagefile = joinpath(root, "Zarr/test/storage.jl")
storage = replace(read(storagefile, String), "if !isnothing(Minio.minio())" => "if false # MinIO unavailable in this worker")
consolidatedfile = joinpath(root, "Zarr/test/consolidated.jl")
consolidated = read(consolidatedfile, String)
# The file imports Python unconditionally. Retain all fixture-independent Julia
# testsets; omit its Python round-trip and the tests requiring absent fixtures.
unitstart = findfirst("  @testset \"v2 consolidate_metadata writes .zmetadata\" begin", consolidated)
ctorstart = findfirst("  @testset \"ConsolidatedStore v3 constructor error paths\" begin", consolidated)
ctorend = findfirst("  @testset \"getmetadata v3 on ConsolidatedStore\" begin", consolidated)
consolidated = "@testset \"Consolidated Metadata (without Python fixtures)\" begin\n" *
    consolidated[first(ctorstart):first(ctorend)-1] * consolidated[first(unitstart):end]
# The final resize! test has one additional fixture-dependent v3 section.
fixturetail = findfirst("    # v3: the array's own zarr.json", consolidated)
consolidated = consolidated[1:first(fixturetail)-1] * "  end\nend\n"
source = replace(source,
    "include(\"consolidated.jl\")" => "include_string(Main, $(repr(consolidated)), $(repr(consolidatedfile)))",
    "include(\"storage.jl\")" => "include_string(Main, $(repr(storage)), $(repr(storagefile)))",
    "include(\"python.jl\")" => "@info \"Skipping Python integration: micromamba lazy artifact unavailable\"")
# include_string does not install the task-local include path. Make each
# top-level relative include absolute while retaining @__DIR__ in the filename.
source = replace(source, r"include\(\"([^\"]+)\"\)" => s -> begin
    name = match(r"include\(\"([^\"]+)\"\)", s).captures[1]
    "include(" * repr(joinpath(dirname(testfile), name)) * ")"
end)
include_string(Main, source, testfile)
