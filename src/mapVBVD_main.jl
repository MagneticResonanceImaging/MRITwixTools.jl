"""
    get_bit(number, pos)

Get bit at position `pos` (0-indexed) from `number`.
"""
get_bit(number, pos) = (number >> pos) & 1

"""
    set_bit(v, index, x)

Set the bit at position `index` (0-indexed) to `x` (true/false).
"""
function set_bit(v, index, x::Bool)
    mask = one(typeof(v)) << index
    v &= ~mask
    if x
        v |= mask
    end
    return v
end

# Vectorized versions
get_bit(numbers::AbstractVector, pos) = (numbers .>> pos) .& 1
function set_bit(vs::AbstractVector, index, x::Bool)
    mask = one(eltype(vs)) << index
    out = vs .& (~mask)
    if x
        out .|= mask
    end
    return out
end

"""
    loop_mdh_read(fid, version, Nscans, scan, measOffset, measLength; print_prog=true)

Read all MDHs (measurement data headers) from the twix file.
Returns (mdh_blob, filePos, isEOF).
"""
function loop_mdh_read(fid::IO, version::String, Nscans::Int, scan::Int,
                       measOffset::UInt64, measLength::UInt64;
                       print_prog::Bool=true)
    if version == "vb"
        isVD = false
        byteMDH = 128
    elseif version == "vd"
        isVD = true
        byteMDH = 184
        szScanHeader = 192
        szChannelHeader = 32
    else
        isVD = false
        byteMDH = 128
        @warn "Software version \"$version\" is not supported."
    end

    cPos = position(fid)
    n_acq = 0
    allocSize = 4096
    ulDMALength = byteMDH
    isEOF = false

    mdh_blob = zeros(UInt8, byteMDH, 0)
    szBlob = size(mdh_blob, 2)
    filePos = Float64[]

    seek(fid, cPos)

    bit_0 = UInt8(1)
    bit_5 = UInt8(32)
    mdhStart = -byteMDH

    u8_000 = zeros(UInt8, 3)

    # Offset for evalInfoMask (1-indexed)
    evIdx = (21 + 20 * isVD)  # 1-based
    dmaIdx = collect(29:32) .+ 20 * isVD  # 1-based
    if isVD
        dmaOff = szScanHeader
        dmaSkip = szChannelHeader
    else
        dmaOff = 0
        dmaSkip = byteMDH
    end

    if print_prog
        p = Progress(Int(measLength), desc=@sprintf("Scan %d/%d, read all mdhs ", scan + 1, Nscans),
                     showspeed=true, enabled=true)
        last_progress = 0
    end

    data_u8 = Vector{UInt8}(undef, -mdhStart)

    while true
        try
            skip(fid, Int(ulDMALength) + mdhStart)
            actual = readbytes!(fid, data_u8, -mdhStart)
            if actual < -mdhStart
                throw(EOFError())
            end
        catch e
            if e isa EOFError || e isa SystemError
                @warn "Unexpected read error at byte offset $cPos ($(cPos / 1024^3) GiB). Will stop reading."
                isEOF = true
                break
            end
            rethrow(e)
        end

        bitMask = data_u8[evIdx]

        if (data_u8[1:3] == u8_000) || (bitMask & bit_0 != 0)
            data_u8[4] = UInt8(get_bit(data_u8[4], 0))
            tmp = reinterpret(UInt32, data_u8[1:4])[1]
            ulDMALength = Int(tmp)

            if ulDMALength == 0 || (bitMask & bit_0 != 0)
                cPos += ulDMALength
                if cPos % 512 != 0
                    cPos += 512 - cPos % 512
                end
                break
            end
        end

        if bitMask & bit_5 != 0  # MDH_SYNCDATA
            data_u8[4] = UInt8(get_bit(data_u8[4], 0))
            tmp = reinterpret(UInt32, data_u8[1:4])[1]
            ulDMALength = Int(tmp)
            cPos += ulDMALength
            continue
        end

        # Correct DMA length using NCol and NCha
        NCol_NCha = reinterpret(UInt16, data_u8[dmaIdx])
        ulDMALength = dmaOff + (8 * Int(NCol_NCha[1]) + dmaSkip) * Int(NCol_NCha[2])

        n_acq += 1

        # Grow arrays in batches
        if n_acq > szBlob
            mdh_blob = hcat(mdh_blob, zeros(UInt8, byteMDH, allocSize))
            append!(filePos, zeros(Float64, allocSize))
            szBlob = size(mdh_blob, 2)
        end

        mdh_blob[:, n_acq] = data_u8
        if n_acq > length(filePos)
            append!(filePos, zeros(Float64, allocSize))
        end
        filePos[n_acq] = Float64(cPos)

        if print_prog
            curr_progress = cPos
            progress = curr_progress - last_progress
            if progress > 0
                ProgressMeter.update!(p, Int(min(curr_progress, measLength)))
            end
            last_progress = curr_progress
        end

        cPos += Int(ulDMALength)
    end

    if isEOF
        n_acq = max(n_acq - 1, 0)
    end

    if n_acq < length(filePos)
        if n_acq + 1 <= length(filePos)
            filePos[n_acq + 1] = Float64(cPos)
        else
            push!(filePos, Float64(cPos))
        end
    else
        push!(filePos, Float64(cPos))
    end

    # Discard overallocation
    mdh_blob = mdh_blob[:, 1:n_acq]
    filePos = filePos[1:n_acq]

    if print_prog
        finish!(p)
    end

    return mdh_blob, filePos, isEOF
end

struct EOFError <: Exception end

"""
    evalMDH(mdh_blob, version)

Parse MDH binary blob into structured MDH and mask objects.
"""
function evalMDH(mdh_blob::Matrix{UInt8}, version::String)
    if version == "vd"
        isVD = true
        # Remove 20 unnecessary bytes (rows 21:40 in 1-based indexing)
        mdh_blob = vcat(mdh_blob[1:20, :], mdh_blob[41:end, :])
    else
        isVD = false
    end

    Nmeas = size(mdh_blob, 2)

    ulPackBit = UInt8.(get_bit(mdh_blob[4, :], 2))
    ulPCI_rx = set_bit(mdh_blob[4, :], 7, false)
    ulPCI_rx = set_bit(Int16.(ulPCI_rx), 8, false)
    mdh_blob[4, :] = UInt8.(get_bit(mdh_blob[4, :], 1))

    # Reinterpret as uint32 (first 76 bytes)
    data_uint32 = Matrix{UInt32}(undef, Nmeas, 19)
    for col in 1:Nmeas
        data_uint32[col, :] = reinterpret(UInt32, mdh_blob[1:76, col])
    end

    # Reinterpret as uint16 (bytes 29 onwards)
    nbytes_u16 = size(mdh_blob, 1) - 28
    nwords_u16 = div(nbytes_u16, 2)
    data_uint16 = Matrix{UInt16}(undef, Nmeas, nwords_u16)
    for col in 1:Nmeas
        data_uint16[col, :] = reinterpret(UInt16, mdh_blob[29:28+nwords_u16*2, col])
    end

    # Reinterpret as float32 (bytes 69 onwards)
    nbytes_f32 = size(mdh_blob, 1) - 68
    nwords_f32 = div(nbytes_f32, 4)
    data_single = Matrix{Float32}(undef, Nmeas, nwords_f32)
    for col in 1:Nmeas
        data_single[col, :] = reinterpret(Float32, mdh_blob[69:68+nwords_f32*4, col])
    end

    # Slice positions and ice parameters depend on VD vs VB
    if isVD
        SlicePos = data_single[:, 4:10]
        aushIceProgramPara = data_uint16[:, 41:64]
        aushFreePara = data_uint16[:, 65:68]
    else
        SlicePos = data_single[:, 8:14]
        aushIceProgramPara = data_uint16[:, 27:30]
        aushFreePara = data_uint16[:, 31:34]
    end

    mdh = MDH(
        ulPackBit,
        ulPCI_rx,
        SlicePos,
        aushIceProgramPara,
        aushFreePara,
        data_uint32[:, 2],    # lMeasUID
        data_uint32[:, 3],    # ulScanCounter
        data_uint32[:, 4],    # ulTimeStamp
        data_uint32[:, 5],    # ulPMUTimeStamp
        data_uint32[:, 6:7],  # aulEvalInfoMask
        data_uint16[:, 1],    # ushSamplesInScan
        data_uint16[:, 2],    # ushUsedChannels
        data_uint16[:, 3:16], # sLC
        data_uint16[:, 17:18],# sCutOff
        data_uint16[:, 19],   # ushKSpaceCentreColumn
        data_uint16[:, 20],   # ushCoilSelect
        data_single[:, 1],    # fReadOutOffcentre
        data_uint32[:, 19],   # ulTimeSinceLastRF
        data_uint16[:, 25],   # ushKSpaceCentreLineNo
        data_uint16[:, 26]    # ushKSpaceCentrePartitionNo
    )

    evalInfoMask1 = mdh.aulEvalInfoMask[:, 1]

    mask = MDHMask(
        min.(evalInfoMask1 .& UInt32(2^0),  UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^1),  UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^2),  UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^5),  UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^10), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^14), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^15), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^17), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^21), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^22), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^23), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^24), UInt32(1)),
        min.(evalInfoMask1 .& UInt32(2^25), UInt32(1)),
        min.(mdh.aulEvalInfoMask[:, 2] .& UInt32(2^(53-32)), UInt32(1)),
        ones(UInt32, Nmeas)
    )

    noImaScan = (mask.MDH_ACQEND .| mask.MDH_RTFEEDBACK .| mask.MDH_HPFEEDBACK
                 .| mask.MDH_PHASCOR .| mask.MDH_NOISEADJSCAN .| mask.MDH_PHASESTABSCAN
                 .| mask.MDH_REFPHASESTABSCAN .| mask.MDH_SYNCDATA
                 .| (mask.MDH_PATREFSCAN .& .~(mask.MDH_PATREFANDIMASCAN)))

    mask.MDH_IMASCAN .-= noImaScan

    return mdh, mask
end


"""
    TwixObj

Result object from mapVBVD. Contains header and scan data objects
accessible via attribute-style access.
"""
mutable struct TwixObj
    _data::Dict{String,Any}
end

TwixObj() = TwixObj(Dict{String,Any}())

Base.getindex(t::TwixObj, key::String) = t._data[key]
Base.setindex!(t::TwixObj, value, key::String) = (t._data[key] = value)
Base.haskey(t::TwixObj, key::String) = haskey(t._data, key)
Base.keys(t::TwixObj) = keys(t._data)
Base.delete!(t::TwixObj, key::String) = delete!(t._data, key)
Base.pop!(t::TwixObj, key::String, default=nothing) = pop!(t._data, key, default)

function Base.getproperty(t::TwixObj, name::Symbol)
    if name === :_data
        return getfield(t, :_data)
    end
    key = String(name)
    if haskey(t._data, key)
        return t._data[key]
    else
        error("TwixObj has no field '$key'")
    end
end

function Base.setproperty!(t::TwixObj, name::Symbol, val)
    if name === :_data
        return setfield!(t, :_data, val)
    end
    t._data[String(name)] = val
end

function Base.show(io::IO, t::TwixObj)
    ks = collect(keys(t._data))
    mdh_keys = filter(k -> k != "hdr", ks)
    println(io, "TwixObj with keys: ", join(ks, ", "))
    if !isempty(mdh_keys)
        println(io, "MDH flags: ", join(mdh_keys, ", "))
    end
end

"""
    MDH_flags(t::TwixObj)

Return list of populated MDH flag names.
"""
function MDH_flags(t::TwixObj)
    return filter(k -> k != "hdr", collect(keys(t._data)))
end

"""
    search_header_for_keys(t::TwixObj, search_terms; kwargs...)

Search header keys for matching terms.
"""
function search_header_for_keys(t::TwixObj, search_terms; kwargs...)
    return search_for_keys(t._data["hdr"], search_terms; kwargs...)
end

"""
    search_header_for_val(t::TwixObj, top_lvl, search_keys; kwargs...)

Search for header values matching given keys.
"""
function search_header_for_val(t::TwixObj, top_lvl, search_keys; kwargs...)
    keys_found = search_for_keys(t._data["hdr"], search_keys;
                                  print_flag=false, top_lvl=top_lvl, kwargs...)
    out_vals = []
    for (key, skeys) in keys_found
        for skey in skeys
            push!(out_vals, t._data["hdr"][key][skey])
        end
    end
    return out_vals
end


"""
    _check_lfs_pointer(filename)

Check if a file is a Git LFS pointer instead of actual binary data.
Throws an informative error if so.
"""
function _check_lfs_pointer(filename::String)
    filesize(filename) < 1024 || return  # LFS pointers are tiny
    open(filename, "r") do f
        header = Vector{UInt8}(undef, min(filesize(filename), 50))
        readbytes!(f, header)
        str = String(header)
        if startswith(str, "version https://git-lfs.github.com")
            error(
                "The file '$(basename(filename))' is a Git LFS pointer, not actual binary data.\n" *
                "Please install Git LFS and run `git lfs pull` to download the real files,\n" *
                "or download them directly from the GitHub repository."
            )
        end
    end
end

"""
    mapVBVD(filename; quiet=false, kwargs...)

Read a Siemens twix (.dat) file. Returns a `TwixObj` for single-raid files
or a `Vector{TwixObj}` for multi-raid (VD+) files.

# Keyword Arguments
- `quiet::Bool=false`: Suppress progress output
- `bReadHeader::Bool=true`: Whether to read the header
- `bReadMDH::Bool=true`: Whether to read MDH data
- Other kwargs are forwarded to `TwixMapObj` constructors
"""
function mapVBVD(filename::String; quiet::Bool=false, kwargs...)
    if !quiet
        println("MapVBVD.jl")
    end

    # Check for Git LFS pointer files
    _check_lfs_pointer(filename)

    bReadHeader = get(kwargs, :bReadHeader, true)
    bReadMDH = get(kwargs, :bReadMDH, true)

    fid = open(filename, "r")

    seekend(fid)
    fileSize = position(fid)

    seek(fid, 0)
    firstInt = read(fid, UInt32)
    secondInt = read(fid, UInt32)

    if (firstInt < 10000) && (secondInt <= 64)
        version = "vd"
        if !quiet
            println("Software version: VD")
        end

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
        if !quiet
            println("Software version: VB")
        end

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
            # Forward kwargs to TwixMapObj, filtering out our own kwargs
            tmo_kwargs = Dict{Symbol,Any}()
            for (k, v) in kwargs
                if k ∉ (:bReadHeader, :bReadMDH, :quiet)
                    tmo_kwargs[k] = v
                end
            end

            mytmo(dtype) = TwixMapObj(dtype, filename, version, rstraj; tmo_kwargs...)

            currTwixObj["image"] = mytmo("image")
            currTwixObj["noise"] = mytmo("noise")
            currTwixObj["phasecor"] = mytmo("phasecor")
            currTwixObj["phasestab"] = mytmo("phasestab")
            currTwixObj["phasestab_ref0"] = mytmo("phasestab_ref0")
            currTwixObj["phasestab_ref1"] = mytmo("phasestab_ref1")
            currTwixObj["refscan"] = mytmo("refscan")
            currTwixObj["refscanPC"] = mytmo("refscanPC")
            currTwixObj["refscan_phasestab"] = mytmo("refscan_phasestab")
            currTwixObj["refscan_phasestab_ref0"] = mytmo("refscan_phasestab_ref0")
            currTwixObj["refscan_phasestab_ref1"] = mytmo("refscan_phasestab_ref1")
            currTwixObj["rtfeedback"] = mytmo("rtfeedback")
            currTwixObj["vop"] = mytmo("vop")

            # Jump to first MDH
            cPos += hdr_len
            seek(fid, cPos)

            mdh_blob, filePos, isEOF = loop_mdh_read(fid, version, NScans, s - 1,
                                                      measOffset[s], measLength[s],
                                                      print_prog=!quiet)

            mdh, mask = evalMDH(mdh_blob, version)

            # --- Assign MDHs to respective scan types ---

            # MDH_IMASCAN
            isCurrScan = Bool.(mask.MDH_IMASCAN)
            if any(isCurrScan)
                readMDH!(currTwixObj["image"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "image")
            end

            # MDH_NOISEADJSCAN
            isCurrScan = Bool.(mask.MDH_NOISEADJSCAN)
            if any(isCurrScan)
                readMDH!(currTwixObj["noise"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "noise")
            end

            # MDH_PATREFSCAN (refscan)
            isCurrScan = Bool.((mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)
                .& .~(mask.MDH_PHASCOR
                    .| mask.MDH_PHASESTABSCAN
                    .| mask.MDH_REFPHASESTABSCAN
                    .| mask.MDH_RTFEEDBACK
                    .| mask.MDH_HPFEEDBACK))
            if any(isCurrScan)
                readMDH!(currTwixObj["refscan"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "refscan")
            end

            # MDH_RTFEEDBACK
            isCurrScan = Bool.((mask.MDH_RTFEEDBACK .| mask.MDH_HPFEEDBACK) .& .~mask.MDH_VOP)
            if any(isCurrScan)
                readMDH!(currTwixObj["rtfeedback"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "rtfeedback")
            end

            # VOP
            isCurrScan = Bool.(mask.MDH_RTFEEDBACK .& mask.MDH_VOP)
            if any(isCurrScan)
                readMDH!(currTwixObj["vop"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "vop")
            end

            # MDH_PHASCOR
            isCurrScan = Bool.(mask.MDH_PHASCOR .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["phasecor"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "phasecor")
            end

            # refscanPC
            isCurrScan = Bool.(mask.MDH_PHASCOR .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["refscanPC"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "refscanPC")
            end

            # phasestab
            isCurrScan = Bool.((mask.MDH_PHASESTABSCAN .& .~mask.MDH_REFPHASESTABSCAN)
                .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["phasestab"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "phasestab")
            end

            # refscan_phasestab
            isCurrScan = Bool.((mask.MDH_PHASESTABSCAN .& .~mask.MDH_REFPHASESTABSCAN)
                .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["refscan_phasestab"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "refscan_phasestab")
            end

            # phasestab_ref0
            isCurrScan = Bool.((mask.MDH_REFPHASESTABSCAN .& .~mask.MDH_PHASESTABSCAN)
                .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["phasestab_ref0"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "phasestab_ref0")
            end

            # refscan_phasestab_ref0
            isCurrScan = Bool.((mask.MDH_REFPHASESTABSCAN .& .~mask.MDH_PHASESTABSCAN)
                .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["refscan_phasestab_ref0"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "refscan_phasestab_ref0")
            end

            # phasestab_ref1
            isCurrScan = Bool.((mask.MDH_REFPHASESTABSCAN .& mask.MDH_PHASESTABSCAN)
                .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["phasestab_ref1"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "phasestab_ref1")
            end

            # refscan_phasestab_ref1
            isCurrScan = Bool.((mask.MDH_REFPHASESTABSCAN .& mask.MDH_PHASESTABSCAN)
                .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN))
            if any(isCurrScan)
                readMDH!(currTwixObj["refscan_phasestab_ref1"], mdh, filePos, isCurrScan)
            else
                delete!(currTwixObj, "refscan_phasestab_ref1")
            end

            if isEOF
                for key in collect(keys(currTwixObj._data))
                    if key != "hdr"
                        tryAndFixLastMdh!(currTwixObj[key])
                    end
                end
            else
                for key in collect(keys(currTwixObj._data))
                    if key != "hdr"
                        clean!(currTwixObj[key])
                    end
                end
            end
        end

        push!(twix_obj, currTwixObj)
    end

    close(fid)

    if length(twix_obj) == 1
        return twix_obj[1]
    end
    return twix_obj
end