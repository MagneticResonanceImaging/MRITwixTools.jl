# ─── Bit operations ──────────────────────────────────────────────────

"""Get bit at position `pos` (0-indexed) from `number`."""
get_bit(number, pos) = (number >> pos) & 1

"""Set the bit at position `index` (0-indexed) to `x` (true/false)."""
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

# ─── Custom exception ────────────────────────────────────────────────

struct EOFError <: Exception end

# ─── MDH loop reader ─────────────────────────────────────────────────

"""
    loop_mdh_read(fid, version, Nscans, scan, measOffset, measLength; print_prog=true)

Read all MDHs (measurement data headers) from the twix file.
Returns (mdh_blob, filePos, isEOF).
"""
function loop_mdh_read(fid::IO, version::String, Nscans::Int, scan::Int,
                       measOffset::UInt64, measLength::UInt64;
                       print_prog::Bool=true)
    isVD = version == "vd"
    byteMDH = isVD ? MDH_SIZE_VD : MDH_SIZE_VB

    if !(version == "vb" || version == "vd")
        @warn "Software version \"$version\" is not supported."
    end

    cPos = position(fid)
    n_acq = 0
    allocSize = 4096
    ulDMALength = byteMDH
    isEOF = false

    mdh_blob = zeros(UInt8, byteMDH, 0)
    szBlob = size(mdh_blob, 2)
    filePos = Int64[]

    seek(fid, cPos)

    u8_000 = zeros(UInt8, 3)

    # Offset for evalInfoMask (1-indexed)
    evIdx = isVD ? EVAL_INFO_OFFSET_VD : EVAL_INFO_OFFSET_VB
    dmaIdx = isVD ? DMA_IDX_VD : DMA_IDX_VB
    dmaOff = isVD ? VD_SCAN_HEADER_SIZE : 0
    dmaSkip = isVD ? VD_CHANNEL_HEADER_SIZE : byteMDH

    if print_prog
        p = Progress(Int(measLength), desc=@sprintf("Scan %d/%d, read all mdhs ", scan + 1, Nscans),
                     showspeed=true, enabled=true)
        p_finished = false
    end

    mdhStart = -byteMDH
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

        if (data_u8[1:3] == u8_000) || (bitMask & BYTE_BIT_0 != 0)
            data_u8[4] = UInt8(get_bit(data_u8[4], 0))
            tmp = reinterpret(UInt32, data_u8[1:4])[1]
            ulDMALength = Int(tmp)

            if ulDMALength == 0 || (bitMask & BYTE_BIT_0 != 0)
                cPos += ulDMALength
                if cPos % 512 != 0
                    cPos += 512 - cPos % 512
                end
                break
            end
        end

        if bitMask & BYTE_BIT_5 != 0  # MDH_SYNCDATA
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
            append!(filePos, zeros(Int64, allocSize))
            szBlob = size(mdh_blob, 2)
        end

        mdh_blob[:, n_acq] = data_u8
        if n_acq > length(filePos)
            append!(filePos, zeros(Int64, allocSize))
        end
        filePos[n_acq] = Int64(cPos)

        if print_prog && !p_finished
            curr_val = Int(min(cPos, measLength))
            ProgressMeter.update!(p, curr_val)
            if curr_val >= Int(measLength)
                p_finished = true
            end
        end

        cPos += Int(ulDMALength)
    end

    if isEOF
        n_acq = max(n_acq - 1, 0)
    end

    if n_acq < length(filePos)
        if n_acq + 1 <= length(filePos)
            filePos[n_acq + 1] = Int64(cPos)
        else
            push!(filePos, Int64(cPos))
        end
    else
        push!(filePos, Int64(cPos))
    end

    # Discard overallocation
    mdh_blob = mdh_blob[:, 1:n_acq]
    filePos = filePos[1:n_acq]

    if print_prog
        finish!(p)
    end

    return mdh_blob, filePos, isEOF
end

# ─── MDH evaluation ──────────────────────────────────────────────────

"""
    evalMDH(mdh_blob, version) -> (MDH, MDHMask)

Parse MDH binary blob into structured MDH and mask objects.
"""
function evalMDH(mdh_blob::Matrix{UInt8}, version::String)
    isVD = version == "vd"
    if isVD
        # Remove 20 unnecessary bytes (rows 21:40 in 1-based indexing)
        mdh_blob = vcat(mdh_blob[1:20, :], mdh_blob[21+VD_EXTRA_BYTES:end, :])
    end

    Nmeas = size(mdh_blob, 2)

    ulPackBit = UInt8.(get_bit(mdh_blob[4, :], 2))
    ulPCI_rx = set_bit(mdh_blob[4, :], 7, false)
    ulPCI_rx = set_bit(Int16.(ulPCI_rx), 8, false)
    mdh_blob[4, :] = UInt8.(get_bit(mdh_blob[4, :], 1))

    # Reinterpret as uint32
    n_u32 = length(UINT32_RANGE) ÷ sizeof(UInt32)
    data_uint32 = Matrix{UInt32}(undef, Nmeas, n_u32)
    for col in 1:Nmeas
        data_uint32[col, :] = reinterpret(UInt32, mdh_blob[UINT32_RANGE, col])
    end

    # Reinterpret as uint16
    nbytes_u16 = size(mdh_blob, 1) - (UINT16_OFFSET - 1)
    nwords_u16 = nbytes_u16 ÷ 2
    data_uint16 = Matrix{UInt16}(undef, Nmeas, nwords_u16)
    for col in 1:Nmeas
        data_uint16[col, :] = reinterpret(UInt16, mdh_blob[UINT16_OFFSET:UINT16_OFFSET-1+nwords_u16*2, col])
    end

    # Reinterpret as float32
    nbytes_f32 = size(mdh_blob, 1) - (FLOAT32_OFFSET - 1)
    nwords_f32 = nbytes_f32 ÷ 4
    data_single = Matrix{Float32}(undef, Nmeas, nwords_f32)
    for col in 1:Nmeas
        data_single[col, :] = reinterpret(Float32, mdh_blob[FLOAT32_OFFSET:FLOAT32_OFFSET-1+nwords_f32*4, col])
    end

    # Version-dependent fields
    SlicePos = isVD ? data_single[:, F32_SLICE_POS_VD] : data_single[:, F32_SLICE_POS_VB]
    aushIceProgramPara = isVD ? data_uint16[:, U16_ICE_PARAM_VD] : data_uint16[:, U16_ICE_PARAM_VB]
    aushFreePara = isVD ? data_uint16[:, U16_FREE_PARAM_VD] : data_uint16[:, U16_FREE_PARAM_VB]

    mdh = MDH(
        ulPackBit,
        ulPCI_rx,
        SlicePos,
        aushIceProgramPara,
        aushFreePara,
        data_uint32[:, U32_MEAS_UID],
        data_uint32[:, U32_SCAN_COUNTER],
        data_uint32[:, U32_TIMESTAMP],
        data_uint32[:, U32_PMU_TIMESTAMP],
        data_uint32[:, U32_EVAL_INFO_MASK],
        data_uint16[:, U16_SAMPLES_IN_SCAN],
        data_uint16[:, U16_USED_CHANNELS],
        data_uint16[:, U16_SLC],
        data_uint16[:, U16_CUT_OFF],
        data_uint16[:, U16_KSPACE_CENTRE_COL],
        data_uint16[:, U16_COIL_SELECT],
        data_single[:, F32_READOUT_OFFCENTRE],
        data_uint32[:, U32_TIME_SINCE_RF],
        data_uint16[:, U16_KSPACE_CENTRE_LINE],
        data_uint16[:, U16_KSPACE_CENTRE_PART],
    )

    evalInfoMask1 = mdh.aulEvalInfoMask[:, 1]

    mask = MDHMask(
        min.(evalInfoMask1 .& UInt32(1 << BIT_ACQEND),            UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_RTFEEDBACK),        UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_HPFEEDBACK),        UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_SYNCDATA),           UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_RAWDATACORRECTION),  UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_REFPHASESTABSCAN),   UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_PHASESTABSCAN),      UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_SIGNREV),            UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_PHASCOR),            UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_PATREFSCAN),         UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_PATREFANDIMASCAN),   UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_REFLECT),            UInt32(1)),
        min.(evalInfoMask1 .& UInt32(1 << BIT_NOISEADJSCAN),       UInt32(1)),
        min.(mdh.aulEvalInfoMask[:, 2] .& UInt32(1 << (BIT_VOP - 32)), UInt32(1)),
        ones(UInt32, Nmeas),
    )

    noImaScan = (mask.MDH_ACQEND .| mask.MDH_RTFEEDBACK .| mask.MDH_HPFEEDBACK
                 .| mask.MDH_PHASCOR .| mask.MDH_NOISEADJSCAN .| mask.MDH_PHASESTABSCAN
                 .| mask.MDH_REFPHASESTABSCAN .| mask.MDH_SYNCDATA
                 .| (mask.MDH_PATREFSCAN .& .~(mask.MDH_PATREFANDIMASCAN)))

    mask.MDH_IMASCAN .-= noImaScan

    return mdh, mask
end

# ─── TwixObj API functions ────────────────────────────────────────────

"""
    MDH_flags(t::TwixObj)

Return list of populated scan type names (excluding "hdr").
"""
function MDH_flags(t::TwixObj)
    return sort(filter(k -> k != "hdr", collect(keys(t._data))))
end

"""
    search_header_for_keys(t::TwixObj, search_terms; kwargs...)

Search header for matching paths. Returns results in legacy format
(Dict of section => Vector of tuple-keys) for backward compatibility.

For the new API, use `search(t.hdr, terms...)` directly.
"""
function search_header_for_keys(t::TwixObj, search_terms; top_lvl=nothing, print_flag::Bool=true, regex::Bool=true, kwargs...)
    hdr = t._data["hdr"]

    # If top_lvl is specified, search only within that section
    if top_lvl !== nothing
        sections = top_lvl isa AbstractString ? [top_lvl] : collect(top_lvl)
    else
        sections = collect(keys(hdr.data))
    end

    # Build results in the legacy format:
    # Dict{String, Vector} where values are vectors of tuple-path keys
    out = Dict{String,Vector}()
    for section in sections
        if !haskey(hdr.data, section)
            out[section] = []
            continue
        end
        sub = hdr.data[section]
        if !(sub isa NestedDict)
            out[section] = []
            continue
        end

        # Search within this section
        terms = search_terms isa Tuple ? collect(search_terms) : [search_terms]
        results = search(sub, terms...; regex=regex)
        # Convert dotted paths to tuples for backward compatibility
        matching_keys = [Tuple(split(r.first, ".")) for r in results]

        if print_flag
            println("$section:")
            for (r, mk) in zip(results, matching_keys)
                println("\t$mk: $(r.second)")
            end
        end

        out[section] = matching_keys
    end

    return out
end

"""
    search_header_for_val(t::TwixObj, top_lvl, search_keys; kwargs...)

Search for header values matching given keys.
"""
function search_header_for_val(t::TwixObj, top_lvl, search_keys; kwargs...)
    keys_found = search_header_for_keys(t, search_keys;
                                         print_flag=false, top_lvl=top_lvl, kwargs...)
    out_vals = []
    hdr = t._data["hdr"]
    for (section, skeys) in keys_found
        for skey in skeys
            # skey is a tuple of strings; join to dotted path for NestedDict access
            path = join(skey, ".")
            push!(out_vals, hdr.data[section][path])
        end
    end
    return out_vals
end

# ─── LFS pointer detection ───────────────────────────────────────────

"""
    _check_lfs_pointer(filename)

Check if a file is a Git LFS pointer instead of actual binary data.
"""
function _check_lfs_pointer(filename::String)
    filesize(filename) < 1024 || return
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

# ─── Main entry point ────────────────────────────────────────────────

"""
    mapVBVD(filename; quiet=false, kwargs...)

Read a Siemens twix (.dat) file. Returns a `TwixObj` for single-raid files
or a `Vector{TwixObj}` for multi-raid (VD+) files.

# Keyword Arguments
- `quiet::Bool=false`: Suppress progress output
- `bReadHeader::Bool=true`: Whether to read the header
- `bReadMDH::Bool=true`: Whether to read MDH data
- Other kwargs are forwarded to `ScanData` constructors
"""
function mapVBVD(filename::String; quiet::Bool=false, kwargs...)
    if !quiet
        println("MapVBVD.jl")
    end

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
            # Forward kwargs to ScanData, filtering out our own kwargs
            sd_kwargs = Dict{Symbol,Any}()
            for (k, v) in kwargs
                if k ∉ (:bReadHeader, :bReadMDH, :quiet)
                    sd_kwargs[k] = v
                end
            end

            make_scan(dtype) = ScanData(dtype, filename, version, rstraj; sd_kwargs...)

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

"""
    _assign_scans!(obj, mdh, mask, filePos)

Assign MDH data to the appropriate scan type objects based on mask flags.
"""
function _assign_scans!(obj::TwixObj, mdh::MDH, mask::MDHMask, filePos::Vector{Int64})
    function _try_assign!(scan_key, selector::AbstractVector{Bool})
        if any(selector)
            readMDH!(obj[scan_key], mdh, filePos, selector)
        else
            delete!(obj, scan_key)
        end
    end

    # image
    _try_assign!("image", Bool.(mask.MDH_IMASCAN))

    # noise
    _try_assign!("noise", Bool.(mask.MDH_NOISEADJSCAN))

    # refscan
    _try_assign!("refscan", Bool.((mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)
        .& .~(mask.MDH_PHASCOR .| mask.MDH_PHASESTABSCAN .| mask.MDH_REFPHASESTABSCAN
              .| mask.MDH_RTFEEDBACK .| mask.MDH_HPFEEDBACK)))

    # rtfeedback
    _try_assign!("rtfeedback", Bool.((mask.MDH_RTFEEDBACK .| mask.MDH_HPFEEDBACK) .& .~mask.MDH_VOP))

    # vop
    _try_assign!("vop", Bool.(mask.MDH_RTFEEDBACK .& mask.MDH_VOP))

    # phasecor
    _try_assign!("phasecor", Bool.(mask.MDH_PHASCOR .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # refscanPC
    _try_assign!("refscanPC", Bool.(mask.MDH_PHASCOR .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # phasestab
    _try_assign!("phasestab", Bool.((mask.MDH_PHASESTABSCAN .& .~mask.MDH_REFPHASESTABSCAN)
        .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # refscan_phasestab
    _try_assign!("refscan_phasestab", Bool.((mask.MDH_PHASESTABSCAN .& .~mask.MDH_REFPHASESTABSCAN)
        .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # phasestab_ref0
    _try_assign!("phasestab_ref0", Bool.((mask.MDH_REFPHASESTABSCAN .& .~mask.MDH_PHASESTABSCAN)
        .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # refscan_phasestab_ref0
    _try_assign!("refscan_phasestab_ref0", Bool.((mask.MDH_REFPHASESTABSCAN .& .~mask.MDH_PHASESTABSCAN)
        .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # phasestab_ref1
    _try_assign!("phasestab_ref1", Bool.((mask.MDH_REFPHASESTABSCAN .& mask.MDH_PHASESTABSCAN)
        .& (.~mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))

    # refscan_phasestab_ref1
    _try_assign!("refscan_phasestab_ref1", Bool.((mask.MDH_REFPHASESTABSCAN .& mask.MDH_PHASESTABSCAN)
        .& (mask.MDH_PATREFSCAN .| mask.MDH_PATREFANDIMASCAN)))
end
