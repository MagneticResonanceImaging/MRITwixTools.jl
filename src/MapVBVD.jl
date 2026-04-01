module MapVBVD

using FFTW
using Interpolations
using Printf
using ProgressMeter

# Core data structures
include("nested_dict.jl")
include("mdh_constants.jl")
include("types.jl")

# Functionality
include("read_twix_hdr.jl")
include("twix_map_obj.jl")
include("mdh.jl")

# Keep old name as alias for backward compatibility
const TwixMapObj = ScanData

# Public API
export mapVBVD
export fullSize, dataSize, sqzSize, sqzDims, getdata, unsorted
export MDH_flags
export set_flagRemoveOS!, set_flagRampSampRegrid!, set_flagDoAverage!
export set_flagAverageReps!, set_flagAverageSets!, set_flagIgnoreSeg!
export set_flagSkipToFirstLine!, set_flagDisableReflect!

# New API exports
export NestedDict, search, leaves, setpath!

# ─── Main entry point ────────────────────────────────────────────────

"""
    mapVBVD(filename; kwargs...) -> TwixObj or Vector{TwixObj}

Read a Siemens twix (.dat) file. Returns a `TwixObj` for single-raid files
or a `Vector{TwixObj}` for multi-raid (VD+) files.

# Keyword Arguments
- `quiet::Bool=false`: suppress progress output
- `bReadHeader::Bool=true`: whether to read the header
- `bReadMDH::Bool=true`: whether to read MDH data

The following flags are forwarded to each `ScanData` object and control
how data is processed when read via `getdata` / `unsorted`:
- `removeOS::Bool=false`: remove 2× readout oversampling via FFT crop
- `regrid::Bool=false`: regrid non-Cartesian (ramp-sampled) readouts
- `doAverage::Bool=false`: average across the `Ave` dimension
- `averageReps::Bool=false`: average across the `Rep` dimension
- `averageSets::Bool=false`: average across the `Set` dimension
- `ignoreSeg::Bool=false`: collapse the `Seg` dimension
- `squeeze::Bool=false`: drop singleton dimensions from returned arrays
- `disableReflect::Bool=false`: skip readout reflection correction
- `ignoreROoffcenter::Bool=false`: ignore readout off-center shifts during regridding
"""
function mapVBVD(filename::String;
                 quiet::Bool             = false,
                 bReadHeader::Bool       = true,
                 bReadMDH::Bool          = true,
                 removeOS::Bool          = false,
                 regrid::Bool            = false,
                 doAverage::Bool         = false,
                 averageReps::Bool       = false,
                 averageSets::Bool       = false,
                 ignoreSeg::Bool         = false,
                 squeeze::Bool           = false,
                 disableReflect::Bool    = false,
                 ignoreROoffcenter::Bool = false)

    fid = open(filename, "r")

    seekend(fid)
    fileSize = position(fid)

    seek(fid, 0)
    firstInt = read(fid, UInt32)
    secondInt = read(fid, UInt32)

    if (firstInt < 10000) && (secondInt <= 64)
        version = "vd"
        NScans = Int(secondInt)
        measID = read(fid, UInt32)
        fileID = read(fid, UInt32)
        measOffset = zeros(UInt64, NScans)
        measLength = zeros(UInt64, NScans)
        for k in 1:NScans
            measOffset[k] = read(fid, UInt64)
            measLength[k] = read(fid, UInt64)
            skip(fid, 152 - 16)
        end
    else
        version = "vb"
        measOffset = UInt64[0]
        measLength = UInt64[fileSize]
        NScans = 1
    end

    twix_obj = TwixObj[]

    for s in 1:NScans
        cPos = measOffset[s]
        seek(fid, cPos)
        hdr_len = read(fid, UInt32)

        currTwixObj = TwixObj()
        currTwixObjHdr = TwixHdr()

        if bReadHeader
            currTwixObjHdr, rstraj = read_twix_hdr(fid, currTwixObjHdr)
            currTwixObj["hdr"] = currTwixObjHdr
        else
            rstraj = nothing
        end

        if bReadMDH
            make_scan(dtype) = ScanData(dtype, filename, version, rstraj;
                                        removeOS=removeOS, regrid=regrid,
                                        doAverage=doAverage, averageReps=averageReps,
                                        averageSets=averageSets, ignoreSeg=ignoreSeg,
                                        squeeze=squeeze, disableReflect=disableReflect,
                                        ignoreROoffcenter=ignoreROoffcenter)

            for stype in SCAN_TYPES
                currTwixObj[stype] = make_scan(stype)
            end

            # Jump to first MDH
            cPos += hdr_len
            seek(fid, cPos)

            mdh_blob, filePos, isEOF = loop_mdh_read(fid, version, NScans, s - 1,
                                                      measOffset[s], measLength[s],
                                                      print_prog=!quiet)

            mdh, mask = evalMDH(mdh_blob, version)

            # --- Assign MDHs to respective scan types ---
            _assign_scans!(currTwixObj, mdh, mask, filePos)

            if isEOF
                for key in collect(keys(currTwixObj._data))
                    key == "hdr" && continue
                    tryAndFixLastMdh!(currTwixObj[key])
                end
            else
                for key in collect(keys(currTwixObj._data))
                    key == "hdr" && continue
                    compute_dims!(currTwixObj[key])
                end
            end
        end

        push!(twix_obj, currTwixObj)
    end

    close(fid)

    return length(twix_obj) == 1 ? twix_obj[1] : twix_obj
end

end # module
