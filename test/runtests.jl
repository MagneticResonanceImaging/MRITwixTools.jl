using Test
using MapVBVD
using Downloads: Downloads
using HDF5
using SHA: sha256

# ─── Utility: download test data from GitHub LFS ───────────────────────────

const BASE_URL = "https://media.githubusercontent.com/media/wtclarke/pymapvbvd/master/tests/test_data"
const CACHE_DIR = get(ENV, "MAPVBVD_TEST_DATA", joinpath(tempdir(), "mapvbvd_test_data"))

# Expected file sizes (from LFS pointers) to validate downloads
const EXPECTED_SIZES = Dict(
    "meas_MID311_STEAM_wref1_FID115674.dat" => 3692672,
    "meas_MID00305_FID74175_VOI_slaser_wref1.dat" => 38707200,
    "meas_MID111_sLaser_broken_FID4873.dat" => 104801984,
    "meas_MID00255_FID12798_GRE_surf.dat" => 39990784,
    "meas_MID00265_FID12808_FMRI.dat" => 110567936,
    "meas_MID00255_FID12798_GRE_surf.mat" => 24834216,
    "meas_MID00265_FID12808_FMRI.mat" => 141181462,
    "meas_MID00305_FID74175_VOI_slaser_wref1.mat" => 961139,
    "meas_MID311_STEAM_wref1_FID115674.mat" => 944125,
)

function get_test_file(fname::String; max_retries::Int=3)
    mkpath(CACHE_DIR)
    local_path = joinpath(CACHE_DIR, fname)

    # Validate existing file by size
    if isfile(local_path)
        expected = get(EXPECTED_SIZES, fname, nothing)
        if expected !== nothing && filesize(local_path) != expected
            @warn "Cached file $fname has wrong size ($(filesize(local_path)) != $expected), re-downloading..."
            rm(local_path)
        end
    end

    if !isfile(local_path)
        url = "$BASE_URL/$fname"
        for attempt in 1:max_retries
            try
                @info "Downloading $fname (attempt $attempt/$max_retries)..."
                Downloads.download(url, local_path)
                # Verify size
                expected = get(EXPECTED_SIZES, fname, nothing)
                if expected !== nothing && filesize(local_path) != expected
                    error("Downloaded file size $(filesize(local_path)) != expected $expected")
                end
                break
            catch e
                if attempt == max_retries
                    rethrow(e)
                end
                @warn "Download attempt $attempt failed: $e. Retrying..."
                isfile(local_path) && rm(local_path)
                sleep(2^attempt)  # exponential backoff
            end
        end
    end

    return local_path
end

# ─── Unit tests (no data files needed) ─────────────────────────────────────

@testset "MapVBVD.jl" begin

    # ─── NestedDict tests ───────────────────────────────────────────
    @testset "NestedDict" begin
        @testset "basic access" begin
            d = NestedDict()
            d["foo"] = 42
            @test d["foo"] == 42
            @test d.foo == 42
            d.bar = "hello"
            @test d["bar"] == "hello"
            @test haskey(d, "foo")
            @test length(d) == 2
            delete!(d, "foo")
            @test !haskey(d, "foo")
        end

        @testset "setpath! and dot-path access" begin
            d = NestedDict()
            setpath!(d, ["sKSpace", "lBaseResolution"], 256)
            setpath!(d, ["sKSpace", "ucDimension"], 4)
            setpath!(d, ["sTXSPEC", "asNucleusInfo", "0", "tNucleus"], "1H")

            # Dot access
            @test d.sKSpace.lBaseResolution == 256
            @test d.sKSpace.ucDimension == 4
            @test d.sTXSPEC.asNucleusInfo isa NestedDict

            # Path string access
            @test d["sKSpace.lBaseResolution"] == 256
            @test d["sTXSPEC.asNucleusInfo.0.tNucleus"] == "1H"
        end

        @testset "search" begin
            d = NestedDict()
            setpath!(d, ["MeasYaps", "sKSpace", "lBaseResolution"], 256)
            setpath!(d, ["MeasYaps", "sTXSPEC", "asNucleusInfo", "0", "tNucleus"], "1H")
            setpath!(d, ["Phoenix", "sKSpace", "lBaseResolution"], 128)

            results = search(d, "lBaseRes")
            @test length(results) == 2
            paths = [r.first for r in results]
            @test "MeasYaps.sKSpace.lBaseResolution" in paths
            @test "Phoenix.sKSpace.lBaseResolution" in paths

            results2 = search(d, "sTXSPEC", "Nucleus")
            @test length(results2) == 1
            @test results2[1].second == "1H"
        end

        @testset "leaves" begin
            d = NestedDict()
            setpath!(d, ["a", "b"], 1)
            setpath!(d, ["a", "c"], 2)
            setpath!(d, ["d"], 3)

            l = leaves(d)
            @test length(l) == 3
            paths = [r.first for r in l]
            @test "a.b" in paths
            @test "a.c" in paths
            @test "d" in paths
        end

        @testset "tab completion" begin
            d = NestedDict()
            setpath!(d, ["sKSpace", "lBaseResolution"], 256)
            d["xprot_val"] = 42

            names = propertynames(d)
            @test :sKSpace in names
            @test :xprot_val in names
        end

        @testset "merge!" begin
            d1 = NestedDict()
            setpath!(d1, ["a", "b"], 1)
            d2 = NestedDict()
            setpath!(d2, ["a", "c"], 2)
            d2["d"] = 3

            merge!(d1, d2)
            @test d1["a.b"] == 1
            @test d1["a.c"] == 2
            @test d1["d"] == 3
        end

        @testset "error messages" begin
            d = NestedDict()
            d["foo"] = 42
            @test_throws ErrorException d.nonexistent
            @test_throws Exception d["a.b.c"]  # path doesn't exist
        end
    end

    # ─── TwixHdr tests ─────────────────────────────────────────────
    @testset "TwixHdr" begin
        h = MapVBVD.TwixHdr()
        h.data["TestSection"] = NestedDict()
        setpath!(h.data["TestSection"], ["key1", "key2"], 3.14)
        @test h["TestSection"]["key1.key2"] == 3.14
        @test h.TestSection.key1.key2 == 3.14

        # Search through TwixHdr
        results = search(h, "key2")
        @test length(results) == 1
    end

    # ─── parse_ascconv tests ───────────────────────────────────────
    @testset "parse_ascconv" begin
        buffer = """sKSpace.lBaseResolution = 256
sKSpace.ucDimension = 0x4
sTXSPEC.asNucleusInfo[0].tNucleus = "1H"
"""
        result = MapVBVD.parse_ascconv(buffer)

        # Now returns NestedDict with tree structure
        @test result.sKSpace.lBaseResolution == 256.0
        @test result["sTXSPEC.asNucleusInfo.0.tNucleus"] == "\"1H\""

        # Search works on parsed result
        results = search(result, "lBaseRes")
        @test length(results) == 1
        @test results[1].second == 256.0
    end

    # ─── parse_xprot tests ────────────────────────────────────────
    @testset "parse_xprot" begin
        buffer = """<ParamLong."TestParam"> { 42 }
<ParamString."TestStr"> { "hello" }
<ParamDouble."TestDbl"> { <Precision> 6  3.14 }"""
        result = MapVBVD.parse_xprot(buffer)
        @test result["TestParam"] == 42.0
        @test result["TestDbl"] == 3.14
    end

    # ─── cumtrapz tests ──────────────────────────────────────────
    @testset "cumtrapz" begin
        y = [1.0, 2.0, 3.0, 4.0]
        result = MapVBVD.cumtrapz(y)
        @test length(result) == 4
        @test result[1] == 0.0
        @test result[2] ≈ 1.5
        @test result[3] ≈ 4.0
        @test result[4] ≈ 7.5
    end

    # ─── ScanData construction tests ─────────────────────────────
    @testset "ScanData construction" begin
        obj = MapVBVD.ScanData("image", "test.dat", "vd")
        @test obj.dType == "image"
        @test obj.version == "vd"
        @test obj.readinfo.szScanHeader == 192
        @test obj.readinfo.szChannelHeader == 32

        obj_vb = MapVBVD.ScanData("noise", "test.dat", "vb")
        @test obj_vb.readinfo.szScanHeader == 0
        @test obj_vb.readinfo.szChannelHeader == 128
    end

    # ─── Bit operations tests ─────────────────────────────────────
    @testset "Bit operations" begin
        @test MapVBVD.get_bit(0x05, 0) == 1
        @test MapVBVD.get_bit(0x05, 1) == 0
        @test MapVBVD.get_bit(0x05, 2) == 1

        @test MapVBVD.set_bit(0x00, 2, true) == 0x04
        @test MapVBVD.set_bit(0x07, 1, false) == 0x05
    end

    # ─── TwixObj tests ────────────────────────────────────────────
    @testset "TwixObj" begin
        t = MapVBVD.TwixObj()
        t["hdr"] = MapVBVD.TwixHdr()
        t["image"] = MapVBVD.ScanData("image", "test.dat", "vd")
        @test haskey(t, "hdr")
        @test haskey(t, "image")
        @test t.image isa MapVBVD.ScanData
        flags = MDH_flags(t)
        @test "image" in flags
        @test !("hdr" in flags)
    end

    # ─── LFS pointer detection tests ─────────────────────────────
    @testset "LFS pointer detection" begin
        tmp = tempname()
        open(tmp, "w") do f
            write(f, "version https://git-lfs.github.com/spec/v1\noid sha256:abc123\nsize 12345\n")
        end
        @test_throws ErrorException mapVBVD(tmp, quiet=true)
        rm(tmp)
    end

    # ─── Flag setters tests ──────────────────────────────────────
    @testset "Flag setters" begin
        obj = MapVBVD.ScanData("image", "test.dat", "vd")
        obj.flagRemoveOS = false
        @test obj.flags.removeOS == false
        obj.flagRemoveOS = true
        @test obj.flags.removeOS == true

        obj.flagDoAverage = true
        @test obj.flagDoAverage == true
        obj.flagDoAverage = false
        @test obj.flagDoAverage == false

        obj.flagIgnoreSeg = true
        @test obj.flagIgnoreSeg == true

        obj.squeeze = true
        @test obj.flags.squeeze == true

        obj.flagAverageReps = true
        @test obj.flagAverageReps == true
        obj.flagAverageReps = false

        obj.flagAverageSets = true
        @test obj.flagAverageSets == true
        obj.flagAverageSets = false

        obj.flagDisableReflect = true
        @test obj.flagDisableReflect == true
    end

    # ─── ProcessingFlags tests ────────────────────────────────────
    @testset "ProcessingFlags" begin
        f = MapVBVD.ProcessingFlags()
        @test f.removeOS == true    # default
        @test f.squeeze == false    # default
        @test f.doAverage == false  # default

        avg = MapVBVD.average_dim(f)
        @test length(avg) == 16
        @test !any(avg)

        f.doAverage = true
        avg = MapVBVD.average_dim(f)
        @test avg[MapVBVD.DIM_AVE] == true
        @test sum(avg) == 1
    end

    # ─── MDH constants tests ─────────────────────────────────────
    @testset "MDH constants" begin
        @test MapVBVD.MDH_SIZE_VB == 128
        @test MapVBVD.MDH_SIZE_VD == 184
        @test MapVBVD.N_DIMS == 16
        @test length(MapVBVD.DIM_NAMES) == 16
        @test MapVBVD.DIM_NAMES[MapVBVD.DIM_COL] == "Col"
        @test MapVBVD.DIM_NAMES[MapVBVD.DIM_IDE] == "Ide"
    end

    # ─── TwixMapObj alias test ───────────────────────────────────
    @testset "TwixMapObj alias" begin
        @test MapVBVD.TwixMapObj === MapVBVD.ScanData
    end

    # ─── Integration tests with real data from GitHub ───────────────────

    @testset "VB SVS read" begin
        path = get_test_file("meas_MID311_STEAM_wref1_FID115674.dat")
        twixObj = mapVBVD(path, quiet=true)

        @test twixObj isa MapVBVD.TwixObj
        @test haskey(twixObj._data, "image")
        @test haskey(twixObj._data, "hdr")

        @test fullSize(twixObj.image) == [4096, 32, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1]
        @test sqzSize(twixObj.image) == [2048, 32, 2]

        # Header search (new API)
        results = search(twixObj.hdr, "sTXSPEC", "asNucleusInfo")
        @test length(results) > 0
        nuc_results = filter(r -> occursin("tNucleus", r.first), results)
        @test length(nuc_results) > 0

        # Header search (legacy API)
        keys_found = search_header_for_keys(twixObj, ("sTXSPEC", "asNucleusInfo"),
                                             top_lvl="MeasYaps", print_flag=false)
        @test ("sTXSPEC", "asNucleusInfo", "0", "tNucleus") in keys_found["MeasYaps"]

        val = search_header_for_val(twixObj, "MeasYaps",
                                    ("sTXSPEC", "asNucleusInfo", "0", "tNucleus"))
        @test val[1] == "\"1H\""

        # Direct dot-access to header
        @test twixObj.hdr.MeasYaps.sTXSPEC.asNucleusInfo isa NestedDict
    end

    @testset "VE SVS read" begin
        path = get_test_file("meas_MID00305_FID74175_VOI_slaser_wref1.dat")
        twixObj = mapVBVD(path, quiet=true)

        @test twixObj isa Vector
        @test length(twixObj) == 2
        @test haskey(twixObj[2]._data, "image")

        @test fullSize(twixObj[2].image) == [4096, 32, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1]
        @test sqzSize(twixObj[2].image) == [2048, 32, 2]

        keys_found = search_header_for_keys(twixObj[2], ("sTXSPEC", "asNucleusInfo"),
                                             top_lvl="MeasYaps", print_flag=false)
        @test ("sTXSPEC", "asNucleusInfo", "0", "tNucleus") in keys_found["MeasYaps"]

        val = search_header_for_val(twixObj[2], "MeasYaps",
                                    ("sTXSPEC", "asNucleusInfo", "0", "tNucleus"))
        @test val[1] == "\"1H\""
    end

    @testset "VB broken file read" begin
        path = get_test_file("meas_MID111_sLaser_broken_FID4873.dat")
        twixObj = @test_warn r"Unexpected read error" mapVBVD(path, quiet=true)

        @test twixObj isa MapVBVD.TwixObj
        @test haskey(twixObj._data, "image")

        @test fullSize(twixObj.image) == [4096, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
        @test sqzSize(twixObj.image) == [2048, 32, 97]

        keys_found = search_header_for_keys(twixObj, ("sTXSPEC", "asNucleusInfo"),
                                             top_lvl="MeasYaps", print_flag=false)
        @test ("sTXSPEC", "asNucleusInfo", "0", "tNucleus") in keys_found["MeasYaps"]

        val = search_header_for_val(twixObj, "MeasYaps",
                                    ("sTXSPEC", "asNucleusInfo", "0", "tNucleus"))
        @test val[1] == "\"1H\""
    end

    @testset "GRE flags (flagRemoveOS)" begin
        path = get_test_file("meas_MID00255_FID12798_GRE_surf.dat")
        twixObj = mapVBVD(path, quiet=true)

        twixObj[2].image.flagRemoveOS = false
        @test dataSize(twixObj[2].image) == [256, 16, 128, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        twixObj[2].image.flagRemoveOS = true
        @test dataSize(twixObj[2].image) == [128, 16, 128, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    end

    @testset "VB broken flagRemoveOS" begin
        path = get_test_file("meas_MID111_sLaser_broken_FID4873.dat")
        twixObj = @test_warn r"Unexpected read error" mapVBVD(path, quiet=true)

        twixObj.image.flagRemoveOS = false
        @test dataSize(twixObj.image) == [4096, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
        twixObj.image.flagRemoveOS = true
        @test dataSize(twixObj.image) == [2048, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
    end

    @testset "EPI flags (flagIgnoreSeg, flagDoAverage)" begin
        path = get_test_file("meas_MID00265_FID12808_FMRI.dat")
        twixObj = mapVBVD(path, quiet=true)

        twixObj[2].refscanPC.flagIgnoreSeg = false
        twixObj[2].refscanPC.flagDoAverage = false
        @test dataSize(twixObj[2].refscanPC) == [110, 16, 1, 1, 5, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
        twixObj[2].refscanPC.flagDoAverage = true
        @test dataSize(twixObj[2].refscanPC) == [110, 16, 1, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]

        twixObj[2].refscanPC.flagIgnoreSeg = true
        twixObj[2].refscanPC.flagDoAverage = false
        @test dataSize(twixObj[2].refscanPC) == [110, 16, 1, 1, 5, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        twixObj[2].refscanPC.flagDoAverage = true
        @test dataSize(twixObj[2].refscanPC) == [110, 16, 1, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    end

    @testset "EPI flagSkipToFirstLine" begin
        path = get_test_file("meas_MID00265_FID12808_FMRI.dat")
        twixObj = mapVBVD(path, quiet=true)

        twixObj[2].refscan.flagSkipToFirstLine = false
        @test dataSize(twixObj[2].refscan) == [110, 16, 82, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
        twixObj[2].refscan.flagSkipToFirstLine = true
        @test dataSize(twixObj[2].refscan) == [110, 16, 54, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
    end

    # ─── Data comparison tests against MATLAB reference (.mat files) ────

    @testset "GRE data vs MATLAB reference" begin
        dat_path = get_test_file("meas_MID00255_FID12798_GRE_surf.dat")
        mat_path = get_test_file("meas_MID00255_FID12798_GRE_surf.mat")

        twixObj = mapVBVD(dat_path, quiet=true)
        twixObj[2].image.squeeze = true

        # Without OS removal
        twixObj[2].image.flagRemoveOS = false
        img_jl = getdata(twixObj[2].image)

        # With OS removal
        twixObj[2].image.flagRemoveOS = true
        img_jl_os = getdata(twixObj[2].image)

        # Read MATLAB reference and compare
        h5open(mat_path, "r") do f
            function to_complex(raw)
                if eltype(raw) <: NamedTuple
                    return map(x -> ComplexF64(x.real, x.imag), raw)
                else
                    return ComplexF64.(raw)
                end
            end

            img_mat_full = to_complex(read(f["img"]))
            img_os_mat_full = to_complex(read(f["img_os"]))

            img_mat = img_mat_full[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_mat_full))...]
            img_os_mat = img_os_mat_full[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_os_mat_full))...]

            img_jl_slice = img_jl[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_jl))...]
            img_jl_os_slice = img_jl_os[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_jl_os))...]

            @test size(img_jl_slice) == size(img_mat)
            @test size(img_jl_os_slice) == size(img_os_mat)

            @test isapprox(ComplexF32.(img_jl_slice), ComplexF32.(img_mat), atol=1e-5)
            @test isapprox(ComplexF32.(img_jl_os_slice), ComplexF32.(img_os_mat), atol=1e-5)
        end
    end

end
