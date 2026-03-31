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

    @testset "AttrDict" begin
        d = MapVBVD.AttrDict()
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

    @testset "TwixHdr" begin
        h = MapVBVD.TwixHdr()
        h.data["TestSection"] = MapVBVD.AttrDict()
        h.data["TestSection"][("key1", "key2")] = 3.14
        @test h["TestSection"][("key1", "key2")] == 3.14
    end

    @testset "parse_ascconv" begin
        buffer = """### ASCCONV BEGIN ###
sKSpace.lBaseResolution = 256
sKSpace.ucDimension = 0x4
sTXSPEC.asNucleusInfo[0].tNucleus = "1H"
### ASCCONV END ###"""
        result = MapVBVD.parse_ascconv(buffer)
        @test haskey(result, ("sKSpace", "lBaseResolution"))
        @test result[("sKSpace", "lBaseResolution")] == 256.0
    end

    @testset "parse_xprot" begin
        buffer = """<ParamLong."TestParam"> { 42 }
<ParamString."TestStr"> { "hello" }
<ParamDouble."TestDbl"> { <Precision> 6  3.14 }"""
        result = MapVBVD.parse_xprot(buffer)
        @test result["TestParam"] == 42.0
        @test result["TestDbl"] == 3.14
    end

    @testset "cumtrapz" begin
        y = [1.0, 2.0, 3.0, 4.0]
        result = MapVBVD.cumtrapz(y)
        @test length(result) == 4
        @test result[1] == 0.0
        @test result[2] ≈ 1.5
        @test result[3] ≈ 4.0
        @test result[4] ≈ 7.5
    end

    @testset "TwixMapObj construction" begin
        obj = MapVBVD.TwixMapObj("image", "test.dat", "vd")
        @test obj.dType == "image"
        @test obj.softwareVersion == "vd"
        @test obj.freadInfo.szScanHeader == 192
        @test obj.freadInfo.szChannelHeader == 32

        obj_vb = MapVBVD.TwixMapObj("noise", "test.dat", "vb")
        @test obj_vb.freadInfo.szScanHeader == 0
        @test obj_vb.freadInfo.szChannelHeader == 128
    end

    @testset "Bit operations" begin
        @test MapVBVD.get_bit(0x05, 0) == 1
        @test MapVBVD.get_bit(0x05, 1) == 0
        @test MapVBVD.get_bit(0x05, 2) == 1

        @test MapVBVD.set_bit(0x00, 2, true) == 0x04
        @test MapVBVD.set_bit(0x07, 1, false) == 0x05
    end

    @testset "TwixObj" begin
        t = MapVBVD.TwixObj()
        t["hdr"] = MapVBVD.TwixHdr()
        t["image"] = MapVBVD.TwixMapObj("image", "test.dat", "vd")
        @test haskey(t, "hdr")
        @test haskey(t, "image")
        @test t.image isa MapVBVD.TwixMapObj
        flags = MDH_flags(t)
        @test "image" in flags
        @test !("hdr" in flags)
    end

    @testset "LFS pointer detection" begin
        tmp = tempname()
        open(tmp, "w") do f
            write(f, "version https://git-lfs.github.com/spec/v1\noid sha256:abc123\nsize 12345\n")
        end
        @test_throws ErrorException mapVBVD(tmp, quiet=true)
        rm(tmp)
    end

    @testset "Flag setters" begin
        obj = MapVBVD.TwixMapObj("image", "test.dat", "vd")
        obj.flagRemoveOS = false
        @test obj.removeOS == false
        obj.flagRemoveOS = true
        @test obj.removeOS == true

        obj.flagDoAverage = true
        @test obj.flagDoAverage == true
        obj.flagDoAverage = false
        @test obj.flagDoAverage == false

        obj.flagIgnoreSeg = true
        @test obj.flagIgnoreSeg == true

        obj.squeeze = true
        @test obj.squeeze_flag == true
    end

    # ─── Integration tests with real data from GitHub ───────────────────

    @testset "VB SVS read" begin
        path = get_test_file("meas_MID311_STEAM_wref1_FID115674.dat")
        twixObj = mapVBVD(path, quiet=true)

        @test twixObj isa MapVBVD.TwixObj
        @test haskey(twixObj._data, "image")
        @test haskey(twixObj._data, "hdr")

        @test fullSize(twixObj.image) ≈ [4096, 32, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1]
        @test sqzSize(twixObj.image) == [2048, 32, 2]

        # Header search
        keys_found = search_header_for_keys(twixObj, ("sTXSPEC", "asNucleusInfo"),
                                             top_lvl="MeasYaps", print_flag=false)
        @test ("sTXSPEC", "asNucleusInfo", "0", "tNucleus") in keys_found["MeasYaps"]

        val = search_header_for_val(twixObj, "MeasYaps",
                                    ("sTXSPEC", "asNucleusInfo", "0", "tNucleus"))
        @test val[1] == "\"1H\""
    end

    @testset "VE SVS read" begin
        path = get_test_file("meas_MID00305_FID74175_VOI_slaser_wref1.dat")
        twixObj = mapVBVD(path, quiet=true)

        @test twixObj isa Vector
        @test length(twixObj) == 2
        @test haskey(twixObj[2]._data, "image")

        @test fullSize(twixObj[2].image) ≈ [4096, 32, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1]
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

        @test fullSize(twixObj.image) ≈ [4096, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
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
        @test dataSize(twixObj[2].image) ≈ [256, 16, 128, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        twixObj[2].image.flagRemoveOS = true
        @test dataSize(twixObj[2].image) ≈ [128, 16, 128, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    end

    @testset "VB broken flagRemoveOS" begin
        path = get_test_file("meas_MID111_sLaser_broken_FID4873.dat")
        twixObj = @test_warn r"Unexpected read error" mapVBVD(path, quiet=true)

        twixObj.image.flagRemoveOS = false
        @test dataSize(twixObj.image) ≈ [4096, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
        twixObj.image.flagRemoveOS = true
        @test dataSize(twixObj.image) ≈ [2048, 32, 1, 1, 1, 1, 1, 1, 1, 97, 1, 1, 1, 1, 1, 1]
    end

    @testset "EPI flags (flagIgnoreSeg, flagDoAverage)" begin
        path = get_test_file("meas_MID00265_FID12808_FMRI.dat")
        twixObj = mapVBVD(path, quiet=true)

        twixObj[2].refscanPC.flagIgnoreSeg = false
        twixObj[2].refscanPC.flagDoAverage = false
        @test dataSize(twixObj[2].refscanPC) ≈ [110, 16, 1, 1, 5, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
        twixObj[2].refscanPC.flagDoAverage = true
        @test dataSize(twixObj[2].refscanPC) ≈ [110, 16, 1, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]

        twixObj[2].refscanPC.flagIgnoreSeg = true
        twixObj[2].refscanPC.flagDoAverage = false
        @test dataSize(twixObj[2].refscanPC) ≈ [110, 16, 1, 1, 5, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        twixObj[2].refscanPC.flagDoAverage = true
        @test dataSize(twixObj[2].refscanPC) ≈ [110, 16, 1, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    end

    @testset "EPI flagSkipToFirstLine" begin
        path = get_test_file("meas_MID00265_FID12808_FMRI.dat")
        twixObj = mapVBVD(path, quiet=true)

        twixObj[2].refscan.flagSkipToFirstLine = false
        @test dataSize(twixObj[2].refscan) ≈ [110, 16, 82, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
        twixObj[2].refscan.flagSkipToFirstLine = true
        @test dataSize(twixObj[2].refscan) ≈ [110, 16, 54, 1, 5, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1]
    end

    # ─── Data comparison tests against MATLAB reference (.mat files) ────
    # These replicate the Python test_read.py tests, comparing extracted
    # data against reference arrays saved by the original MATLAB mapVBVD.

    @testset "GRE data vs MATLAB reference" begin
        dat_path = get_test_file("meas_MID00255_FID12798_GRE_surf.dat")
        mat_path = get_test_file("meas_MID00255_FID12798_GRE_surf.mat")

        twixObj = mapVBVD(dat_path, quiet=true)
        twixObj[2].image.squeeze = true

        # Without OS removal (Python: twixObj[1].image[:, :, :, 0])
        twixObj[2].image.flagRemoveOS = false
        img_jl = getdata(twixObj[2].image)

        # With OS removal
        twixObj[2].image.flagRemoveOS = true
        img_jl_os = getdata(twixObj[2].image)

        # Read MATLAB reference and compare
        h5open(mat_path, "r") do f
            # HDF5.jl reads compound {real,imag} as NamedTuple
            function to_complex(raw)
                if eltype(raw) <: NamedTuple
                    return map(x -> ComplexF64(x.real, x.imag), raw)
                else
                    return ComplexF64.(raw)
                end
            end

            img_mat_full = to_complex(read(f["img"]))
            img_os_mat_full = to_complex(read(f["img_os"]))

            # MATLAB v7.3 HDF5: dimensions are reversed from MATLAB order.
            # Python test takes [0,0,:,:,:] and transposes.
            # In Julia/HDF5 the first dims are the data dims.
            # Select first element of all trailing singleton dims.
            img_mat = img_mat_full[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_mat_full))...]
            img_os_mat = img_os_mat_full[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_os_mat_full))...]

            # Select matching slice from Julia data
            img_jl_slice = img_jl[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_jl))...]
            img_jl_os_slice = img_jl_os[ntuple(i -> i <= 3 ? Colon() : 1, ndims(img_jl_os))...]

            # Verify shapes match
            @test size(img_jl_slice) == size(img_mat)
            @test size(img_jl_os_slice) == size(img_os_mat)

            # Verify data matches
            @test isapprox(ComplexF32.(img_jl_slice), ComplexF32.(img_mat), atol=1e-5)
            @test isapprox(ComplexF32.(img_jl_os_slice), ComplexF32.(img_os_mat), atol=1e-5)
        end
    end

end