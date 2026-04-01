# ─── RawData property interface (flag access) ─────────────────────────

"""
    fullSize(s::RawData) -> Vector{Int}

Return the full 16-element dimension size vector.
"""
function fullSize(s::RawData)
    if s.dims === nothing
        compute_dims!(s)
    end
    d = s.dims
    return Int[d.NCol, d.NCha,
               max(1, d.NLin - d.skipLin), max(1, d.NPar - d.skipPar),
               d.NSli, d.NAve, d.NPhs, d.NEco,
               d.NRep, d.NSet, d.NSeg,
               d.NIda, d.NIdb, d.NIdc, d.NIdd, d.NIde]
end

"""
    dataSize(s::RawData) -> Vector{Int}

Return data size accounting for OS removal and averaging flags.
"""
function dataSize(s::RawData)
    out = fullSize(s)
    avg = average_dim(s)

    if s.removeOS
        out[DIM_COL] = out[DIM_COL] ÷ 2
    end

    if avg[DIM_COL] || avg[DIM_CHA]
        @warn "averaging in Col and Cha dimensions not supported, resetting flags"
        # Can't average Col/Cha
    end

    for i in 1:N_DIMS
        if avg[i]
            out[i] = 1
        end
    end
    return out
end

"""
    sqzSize(s::RawData) -> Vector{Int}

Return data sizes with singleton dimensions removed.
"""
function sqzSize(s::RawData)
    ds = dataSize(s)
    return ds[ds .> 1]
end

"""
    sqzDims(s::RawData) -> Vector{String}

Return dimension names for non-singleton dimensions.
"""
function sqzDims(s::RawData)
    ds = dataSize(s)
    return DIM_NAMES[ds .> 1]
end

# ─── Flag setters ─────────────────────────────────────────────────────

set_flagRemoveOS!(s::RawData, val::Bool) = (s.removeOS = val)

function set_flagRampSampRegrid!(s::RawData, val::Bool)
    if val && s.rstrj === nothing
        error("No trajectory for regridding available")
    end
    s.regrid = val
end

set_flagDoAverage!(s::RawData, val::Bool) = (s.doAverage = val)
set_flagAverageReps!(s::RawData, val::Bool) = (s.averageReps = val)
set_flagAverageSets!(s::RawData, val::Bool) = (s.averageSets = val)
set_flagIgnoreSeg!(s::RawData, val::Bool) = (s.ignoreSeg = val)
set_flagDisableReflect!(s::RawData, val::Bool) = (s.disableReflect = val)

function set_flagSkipToFirstLine!(s::RawData, val::Bool)
    if val != s.skipToFirstLine
        s.skipToFirstLine = val
        _recompute_skip!(s)
    end
end

"""Recompute dims when skipToFirstLine changes."""
function _recompute_skip!(s::RawData)
    s.meta === nothing && return
    m = s.meta
    d = s.dims
    d === nothing && return

    if s.skipToFirstLine
        skipLin = Int(minimum(m.Lin))
        skipPar = Int(minimum(m.Par))
    else
        skipLin = 0
        skipPar = 0
    end

    s.dims = DimSizes(
        d.NCol, d.NCha, d.NLin, d.NPar, d.NSli, d.NAve, d.NPhs, d.NEco,
        d.NRep, d.NSet, d.NSeg, d.NIda, d.NIdb, d.NIdc, d.NIdd, d.NIde,
        skipLin, skipPar
    )
end

# Property aliases for backward compatibility (flagRemoveOS → removeOS, etc.)
function Base.getproperty(s::RawData, name::Symbol)
    name === :flagRemoveOS       && return getfield(s, :removeOS)
    name === :flagRampSampRegrid && return getfield(s, :regrid)
    name === :flagDoAverage      && return getfield(s, :doAverage)
    name === :flagIgnoreSeg      && return getfield(s, :ignoreSeg)
    name === :flagSkipToFirstLine && return getfield(s, :skipToFirstLine)
    name === :flagDisableReflect && return getfield(s, :disableReflect)
    name === :flagAverageReps    && return getfield(s, :averageReps)
    name === :flagAverageSets    && return getfield(s, :averageSets)
    return getfield(s, name)
end

function Base.setproperty!(s::RawData, name::Symbol, val)
    name === :flagRemoveOS       && return set_flagRemoveOS!(s, val)
    name === :flagRampSampRegrid && return set_flagRampSampRegrid!(s, val)
    name === :flagDoAverage      && return set_flagDoAverage!(s, val)
    name === :flagIgnoreSeg      && return set_flagIgnoreSeg!(s, val)
    name === :flagSkipToFirstLine && return set_flagSkipToFirstLine!(s, val)
    name === :flagDisableReflect && return set_flagDisableReflect!(s, val)
    name === :flagAverageReps    && return set_flagAverageReps!(s, val)
    name === :flagAverageSets    && return set_flagAverageSets!(s, val)
    return setfield!(s, name, val)
end

function Base.show(io::IO, s::RawData)
    if s.meta === nothing
        print(io, "RawData ($(s.dType)) [no data loaded]")
    else
        fs = fullSize(s)
        print(io, "RawData ($(s.dType)) ")
        print(io, "$(s.meta.NAcq) acq, size $(sqzSize(s))")
    end
end

function Base.show(io::IO, ::MIME"text/plain", s::RawData)
    if s.meta === nothing
        println(io, "RawData ($(s.dType)) [no data loaded]")
        println(io, "  File: $(s.fname)")
        println(io, "  Software: $(s.version)")
    else
        fs = fullSize(s)
        println(io, "RawData ($(s.dType))")
        println(io, "  File: $(s.fname)")
        println(io, "  Software: $(s.version)")
        println(io, "  Acquisitions: $(s.meta.NAcq)")
        println(io, "  Full size: $fs")
        println(io, "  Squeezed: $(sqzSize(s)) ($(sqzDims(s)))")
    end
end

# ─── MDH reading ─────────────────────────────────────────────────────

"""
    readMDH!(s::RawData, mdh::MDH, filePos, useScan)

Extract MDH values for the selected scans and populate the RawData.
"""
function readMDH!(s::RawData, mdh::MDH, filePos::Vector{Int64}, useScan::AbstractVector{Bool})
    nAcq = sum(useScan)
    sLC = mdh.sLC
    evalInfoMask1 = mdh.aulEvalInfoMask[useScan, 1]

    NCol_vals = mdh.ushSamplesInScan[useScan]
    NCha_vals = mdh.ushUsedChannels[useScan]

    # Assume uniform NCol and NCha
    NCol = Int(NCol_vals[1])
    NCha = Int(NCha_vals[1])

    meta = AcquisitionMeta(
        nAcq,
        # Loop counters
        Int32.(sLC[useScan, 1]),   # Lin
        Int32.(sLC[useScan, 4]),   # Par
        Int32.(sLC[useScan, 3]),   # Sli
        Int32.(sLC[useScan, 2]),   # Ave
        Int32.(sLC[useScan, 6]),   # Phs
        Int32.(sLC[useScan, 5]),   # Eco
        Int32.(sLC[useScan, 7]),   # Rep
        Int32.(sLC[useScan, 8]),   # Set
        Int32.(sLC[useScan, 9]),   # Seg
        Int32.(sLC[useScan, 10]),  # Ida
        Int32.(sLC[useScan, 11]),  # Idb
        Int32.(sLC[useScan, 12]),  # Idc
        Int32.(sLC[useScan, 13]),  # Idd
        Int32.(sLC[useScan, 14]),  # Ide
        # K-space metadata
        Int32.(mdh.ushKSpaceCentreColumn[useScan]),
        Int32.(mdh.ushKSpaceCentreLineNo[useScan]),
        Int32.(mdh.ushKSpaceCentrePartitionNo[useScan]),
        Int32.(mdh.sCutOff[useScan, :]),
        Int32.(mdh.ushCoilSelect[useScan]),
        Float32.(mdh.fReadOutOffcentre[useScan]),
        mdh.ulTimeSinceLastRF[useScan],
        BitVector(min.(evalInfoMask1 .& UInt32(1 << BIT_REFLECT), UInt32(1))),
        BitVector(min.(evalInfoMask1 .& UInt32(1 << BIT_RAWDATACORRECTION), UInt32(1))),
        mdh.ulScanCounter[useScan],
        mdh.ulTimeStamp[useScan],
        mdh.ulPMUTimeStamp[useScan],
        Float32.(mdh.SlicePos[useScan, :]),
        mdh.aushIceProgramPara[useScan, :],
        mdh.aushFreePara[useScan, :],
        # File positions
        filePos[useScan],
        NCol, NCha,
    )

    s.meta = meta
    s.dims = nothing  # force recomputation
end

"""
    tryAndFixLastMdh!(s::RawData)

Attempt to recover from read errors by trimming the last acquisition.
"""
function tryAndFixLastMdh!(s::RawData)
    s.meta === nothing && return

    isLastAcqGood = false
    cnt = 0
    nAcq = s.meta.NAcq

    while !isLastAcqGood && nAcq > 0 && cnt < 100
        try
            unsorted(s, nAcq)
            isLastAcqGood = true
        catch e
            @warn "Error fixing last MDH. NAcq = $nAcq" exception=e
            s.isBrokenFile = true
            nAcq -= 1
        end
        cnt += 1
    end

    # If we trimmed, rebuild meta with fewer acquisitions
    if nAcq < s.meta.NAcq && nAcq > 0
        m = s.meta
        ix = 1:nAcq
        s.meta = AcquisitionMeta(
            nAcq,
            m.Lin[ix], m.Par[ix], m.Sli[ix], m.Ave[ix], m.Phs[ix], m.Eco[ix],
            m.Rep[ix], m.Set[ix], m.Seg[ix], m.Ida[ix], m.Idb[ix], m.Idc[ix],
            m.Idd[ix], m.Ide[ix],
            m.centerCol[ix], m.centerLin[ix], m.centerPar[ix],
            m.cutOff[ix, :], m.coilSelect[ix], m.ROoffcenter[ix],
            m.timeSinceRF[ix], m.IsReflected[ix], m.IsRawDataCorrect[ix],
            m.scancounter[ix], m.timestamp[ix], m.pmutime[ix],
            m.slicePos[ix, :], m.iceParam[ix, :], m.freeParam[ix, :],
            m.memPos[ix], m.NCol, m.NCha,
        )
    end

    compute_dims!(s)
end

"""
    compute_dims!(s::RawData)

Compute dimension sizes from acquisition metadata.
"""
function compute_dims!(s::RawData)
    m = s.meta
    m === nothing && return

    NLin = Int(maximum(m.Lin)) + 1
    NPar = Int(maximum(m.Par)) + 1
    NSli = Int(maximum(m.Sli)) + 1
    NAve = Int(maximum(m.Ave)) + 1
    NPhs = Int(maximum(m.Phs)) + 1
    NEco = Int(maximum(m.Eco)) + 1
    NRep = Int(maximum(m.Rep)) + 1
    NSet = Int(maximum(m.Set)) + 1
    NSeg = Int(maximum(m.Seg)) + 1
    NIda = Int(maximum(m.Ida)) + 1
    NIdb = Int(maximum(m.Idb)) + 1
    NIdc = Int(maximum(m.Idc)) + 1
    NIdd = Int(maximum(m.Idd)) + 1
    NIde = Int(maximum(m.Ide)) + 1

    # Handle refscan wrap-around
    if s.dType == "refscan"
        if NLin > 65500
            minLin = Int(minimum(m.Lin[m.Lin .> 65500]))
            NLin = Int(maximum(mod.(Int.(m.Lin) .+ (65536 - minLin), 65536)))
        end
        if NPar > 65500
            minPar = Int(minimum(m.Par[m.Par .> 65500]))
            NPar = Int(maximum(mod.(Int.(m.Par) .+ (65536 - minPar), 65536)))
        end
    end

    skipLin = s.skipToFirstLine ? Int(minimum(m.Lin)) : 0
    skipPar = s.skipToFirstLine ? Int(minimum(m.Par)) : 0

    s.dims = DimSizes(
        m.NCol, m.NCha, NLin, NPar, NSli, NAve, NPhs, NEco,
        NRep, NSet, NSeg, NIda, NIdb, NIdc, NIdd, NIde,
        skipLin, skipPar
    )

    return nothing
end

# ─── Read info helpers ────────────────────────────────────────────────

"""Compute file read parameters from RawData."""
function _read_params(s::RawData)
    m = s.meta
    ri = s.readinfo
    NCol = m.NCol
    NCha = m.NCha
    shape = (NCol + ri.szChannelHeader ÷ 8, NCha)
    cut = (ri.szChannelHeader ÷ 8 + 1):(ri.szChannelHeader ÷ 8 + NCol)
    return (; shape, cut, NCol, NCha)
end

# ─── Index calculation ────────────────────────────────────────────────

"""
    calcIndices(s::RawData) -> (ixToRaw, ixToTarget)

Calculate mapping from MDH acquisitions to target array positions.
"""
function calcIndices(s::RawData)
    m = s.meta
    fs = fullSize(s)
    d = s.dims
    skipLin = d.skipLin
    skipPar = d.skipPar
    sz = Tuple(fs[3:end])

    n = m.NAcq
    li = LinearIndices(sz)
    ixToTarget = Vector{Int}(undef, n)

    @inbounds for i in 1:n
        ixToTarget[i] = li[
            Int(m.Lin[i]) - skipLin + 1,
            Int(m.Par[i]) - skipPar + 1,
            Int(m.Sli[i]) + 1,
            Int(m.Ave[i]) + 1,
            Int(m.Phs[i]) + 1,
            Int(m.Eco[i]) + 1,
            Int(m.Rep[i]) + 1,
            Int(m.Set[i]) + 1,
            Int(m.Seg[i]) + 1,
            Int(m.Ida[i]) + 1,
            Int(m.Idb[i]) + 1,
            Int(m.Idc[i]) + 1,
            Int(m.Idd[i]) + 1,
            Int(m.Ide[i]) + 1,
        ]
    end

    # Inverse: target -> raw (0 means not acquired)
    total = prod(sz)
    ixToRaw = zeros(Int, total)
    @inbounds for (i, itt) in enumerate(ixToTarget)
        ixToRaw[itt] = i
    end

    return ixToRaw, ixToTarget
end

# ─── Range calculation ────────────────────────────────────────────────

"""
    calcRange(s::RawData, S) -> (selRange, selRangeSz, outSize)

Calculate selection ranges for data retrieval.
"""
function calcRange(s::RawData, S)
    if s.dims === nothing
        compute_dims!(s)
    end
    ds = dataSize(s)
    avg = average_dim(s)

    selRange = [collect(1:ds[k]) for k in 1:N_DIMS]
    outSize = ones(Int, N_DIMS)

    bSqueeze = s.squeeze

    if S === nothing || S === Colon()
        for k in 1:N_DIMS
            selRange[k] = collect(1:ds[k])
        end
        outSize = bSqueeze ? sqzSize(s) : copy(ds)
    else
        for (k, sel) in enumerate(S)
            cDim = if !bSqueeze
                k
            else
                sd = sqzDims(s)
                if k > length(sd)
                    error("Index $k exceeds number of squeezed dimensions ($(length(sd)))")
                end
                findfirst(==(sd[k]), DIM_NAMES)
            end

            if sel === Colon()
                if k < length(S)
                    selRange[cDim] = collect(1:ds[cDim])
                else
                    for ll in cDim:N_DIMS
                        selRange[ll] = collect(1:ds[ll])
                    end
                    outSize[k] = prod(ds[cDim:end])
                    break
                end
            elseif sel isa UnitRange || sel isa StepRange
                selRange[cDim] = collect(sel)
            elseif sel isa Integer
                selRange[cDim] = [sel]
            else
                selRange[cDim] = collect(sel)
            end

            outSize[k] = length(selRange[cDim])
        end
    end

    selRangeSz = [length(r) for r in selRange]

    # Expand selection for averaged dimensions
    for iDx in 1:N_DIMS
        if avg[iDx]
            fs = fullSize(s)
            selRange[iDx] = collect(1:fs[iDx])
        end
    end

    return selRange, selRangeSz, outSize
end

# ─── Unsorted data access ────────────────────────────────────────────

"""
    unsorted(s::RawData, ival=nothing)

Return unsorted data [NCol, NCha, #samples].
"""
function unsorted(s::RawData, ival=nothing)
    m = s.meta
    if ival !== nothing
        mem = [m.memPos[ival]]
    else
        mem = m.memPos
    end
    return readData(s, mem)
end

# ─── Core data reading ───────────────────────────────────────────────

"""
    readData(s, mem; cIxToTarg, cIxToRaw, selRange, selRangeSz, outSize)

Read raw data from file. Core I/O routine.
"""
function readData(s::RawData, mem::AbstractVector{Int64};
                  cIxToTarg=nothing, cIxToRaw=nothing,
                  selRange=nothing, selRangeSz=nothing, outSize=nothing)

    rp = _read_params(s)
    ds = dataSize(s)

    if outSize === nothing
        if selRange === nothing
            selRange = [collect(1:ds[1]), collect(1:ds[2])]
        else
            selRange[1] = collect(1:ds[1])
            selRange[2] = collect(1:ds[2])
        end

        outSize = [ds[1], ds[2], length(mem)]
        selRangeSz = copy(outSize)
        cIxToTarg = collect(1:selRangeSz[3])
        cIxToRaw = copy(cIxToTarg)
    end

    out = zeros(ComplexF32, Tuple(outSize))
    out = reshape(out, selRangeSz[1], selRangeSz[2], :)

    szScanHeader = s.readinfo.szScanHeader
    readShape = rp.shape
    readCut = rp.cut
    NCol_int = rp.NCol

    keepOS = vcat(collect(1:NCol_int÷4), collect(3*NCol_int÷4+1:NCol_int))

    m = s.meta
    bIsReflected = m.IsReflected[cIxToRaw]
    bRegrid = s.regrid && s.rstrj !== nothing && length(s.rstrj) > 1

    ro_shift = Float64.(m.ROoffcenter[cIxToRaw]) .* Float64(!s.ignoreROoffcenter)
    isBrokenRead = false

    # Block processing
    blockSz = 2
    doLockblockSz = false
    tprev = Inf

    blockInit = fill(ComplexF32(-Inf), readShape[1], readShape[2], blockSz)
    block = copy(blockInit)
    blockCtr = 0

    # Regridding setup
    rsTrj = nothing
    trgTrj_x = nothing
    if bRegrid
        rsTrj = s.rstrj
        trgTrj_x = range(minimum(rsTrj), maximum(rsTrj), length=NCol_int)
    end

    count_ave = zeros(Float32, 1, 1, size(out, 3))
    kMax = length(mem)

    fid = open(s.fname, "r")

    # Pre-allocate read buffer as ComplexF32 — Siemens stores interleaved
    # (real, imag) Float32 pairs which have identical memory layout to ComplexF32.
    # This eliminates 3 temporary array allocations per acquisition.
    n_complex = prod(readShape)
    raw_complex = Vector{ComplexF32}(undef, n_complex)
    raw_complex_mat = reshape(raw_complex, readShape[1], readShape[2])

    p = Progress(kMax, desc="read data ", enabled=true)

    for k in 1:kMax
        seek(fid, mem[k] + szScanHeader)
        try
            read!(fid, raw_complex)
        catch
            @warn "Unexpected read error at byte offset $(mem[k] + szScanHeader)"
            fill!(raw_complex, ComplexF32(-Inf))
        end

        block[:, :, blockCtr + 1] = raw_complex_mat
        blockCtr += 1

        if (blockCtr == blockSz) || (k == kMax) || (isBrokenRead && blockCtr > 1)
            tic = time()

            # Remove MDH/channel header data
            blk = block[readCut, :, 1:blockCtr]

            ix = (k - blockCtr + 1):k

            # Reflect
            if !s.disableReflect
                for j in 1:blockCtr
                    if bIsReflected[ix[j]]
                        blk[:, :, j] = blk[end:-1:1, :, j]
                    end
                end
            end

            # Regridding
            if bRegrid
                deltak = maximum(abs.(diff(rsTrj)))
                for j in 1:blockCtr
                    fovshift = ro_shift[ix[j]]
                    adc_range = collect(0:NCol_int-1)
                    adcphase = deltak .* adc_range .* fovshift
                    fovphase = fovshift .* rsTrj
                    phase_factor = exp.(im .* 2π .* (adcphase .- fovphase))
                    for ch in 1:size(blk, 2)
                        blk[:, ch, j] .*= ComplexF32.(phase_factor)
                    end
                end

                for j in 1:blockCtr
                    for ch in 1:size(blk, 2)
                        sig = blk[:, ch, j]
                        itp_r = interpolate((rsTrj,), real.(sig), Gridded(Linear()))
                        itp_i = interpolate((rsTrj,), imag.(sig), Gridded(Linear()))
                        regridded = ComplexF32.(itp_r.(trgTrj_x) .+ im .* itp_i.(trgTrj_x))
                        blk[:, ch, j] = regridded
                    end
                end
            end

            # Remove oversampling
            if s.removeOS
                for j in 1:blockCtr
                    for ch in 1:size(blk, 2)
                        tmp = ifft(blk[:, ch, j])
                        blk_os = tmp[keepOS]
                        blk[keepOS, ch, j] = fft(blk_os)
                    end
                end
                blk = blk[keepOS, :, :]
            end

            # Select ranges
            cur1stDim = length(selRange[1])
            cur2ndDim = length(selRange[2])

            blk_sel = blk[selRange[1], selRange[2], :]
            blk_sel = reshape(blk_sel, cur1stDim, cur2ndDim, :)

            toSort = cIxToTarg[ix]
            II = sortperm(toSort)
            sortIdx = toSort[II]
            blk_sel = blk_sel[:, :, II]

            isDupe = vcat([false], diff(sortIdx) .== 0)

            idx1 = sortIdx[.!isDupe]
            idxN = sortIdx[isDupe]

            count_ave[1, 1, idx1] .+= 1

            if isempty(idxN)
                if all(count_ave[1, 1, idx1] .== 1)
                    out[:, :, idx1] = blk_sel
                else
                    out[:, :, idx1] .+= blk_sel
                end
            else
                out[:, :, idx1] .+= blk_sel[:, :, .!isDupe]

                blk_dupe = blk_sel[:, :, isDupe]
                for n in 1:length(idxN)
                    out[:, :, idxN[n]] .+= blk_dupe[:, :, n]
                    count_ave[1, 1, idxN[n]] += 1
                end
            end

            # Adaptive block sizing
            if !doLockblockSz
                toc = time()
                t = 1e6 * (toc - tic) / blockSz

                if t <= 1.1 * tprev
                    blockSz *= 2
                    blockInit = cat(blockInit, blockInit, dims=3)
                else
                    blockSz = max(blockSz ÷ 2, 1)
                    blockInit = blockInit[:, :, 1:blockSz]
                    doLockblockSz = true
                end
                tprev = t
            end

            blockCtr = 0
            block = copy(blockInit)
        end

        if isBrokenRead
            s.isBrokenFile = true
            break
        end

        next!(p)
    end

    close(fid)

    # Average scaling
    if any(count_ave .> 1)
        count_ave .= max.(count_ave, 1)
        out ./= count_ave
    end

    out = reshape(out, Tuple(outSize))

    if s.squeeze
        return dropdims_all(out)
    else
        return out
    end
end

# ─── getdata ─────────────────────────────────────────────────────────

"""
    getdata(s::RawData; key=nothing)

Retrieve data from the RawData. Pass `key=nothing` for all data,
or a tuple of ranges for slicing.
"""
function getdata(s::RawData; key=nothing)
    selRange, selRangeSz, outSize = calcRange(s, key)
    m = s.meta
    avg = average_dim(s)
    d = s.dims

    ixToRaw, _ = calcIndices(s)

    fs = fullSize(s)
    sz = Tuple(fs[3:end])

    # Build selection from target space
    tmp = reshape(collect(1:prod(sz)), sz)
    for (i, ids) in enumerate(selRange[3:end])
        dims_to_select = ntuple(j -> j == i ? ids : (1:size(tmp, j)), ndims(tmp))
        tmp = tmp[dims_to_select...]
    end

    ixToRaw_sel = ixToRaw[tmp[:]]
    ixToRaw_sel = ixToRaw_sel[ixToRaw_sel .> 0]

    # Calculate ixToTarg for the selected range
    cIx = zeros(Int, 14, length(ixToRaw_sel))
    dim_fields = [
        :Lin, :Par, :Sli, :Ave, :Phs, :Eco,
        :Rep, :Set, :Seg, :Ida, :Idb, :Idc, :Idd, :Ide
    ]
    skip_vals = [d.skipLin, d.skipPar, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for (di, (field, skip_v)) in enumerate(zip(dim_fields, skip_vals))
        if !avg[di + 2]
            vals = getfield(m, field)
            cIx[di, :] = Int.(vals[ixToRaw_sel]) .- skip_v .+ 1  # 1-based
        else
            cIx[di, :] .= 1
        end
    end

    # Map to selection range indices
    for k in 3:length(selRange)
        row = k - 2
        tmp_row = cIx[row, :]
        for ll in 1:length(selRange[k])
            cIx[row, tmp_row .== selRange[k][ll]] .= ll
        end
    end

    szz = Tuple(selRangeSz[3:end])
    ixToTarg = Vector{Int}(undef, size(cIx, 2))
    li = LinearIndices(szz)
    for i in 1:length(ixToTarg)
        idx = ntuple(j -> cIx[j, i], 14)
        ixToTarg[i] = li[idx...]
    end

    mem = m.memPos[ixToRaw_sel]
    ix_sort = sortperm(mem)
    mem = mem[ix_sort]
    ixToTarg = ixToTarg[ix_sort]
    ixToRaw_sel = ixToRaw_sel[ix_sort]

    return readData(s, mem; cIxToTarg=ixToTarg, cIxToRaw=ixToRaw_sel,
                    selRange=selRange, selRangeSz=selRangeSz, outSize=outSize)
end

# Allow obj[:] syntax via getindex
function Base.getindex(s::RawData, args...)
    getdata(s; key=args)
end

# ─── Utilities ────────────────────────────────────────────────────────

"""
    fixLoopCounter!(s, loop, newLoop)

Replace a loop counter with new values. Note: because AcquisitionMeta
is immutable, this rebuilds the entire meta struct.
"""
function fixLoopCounter!(s::RawData, loop::String, newLoop::Vector)
    m = s.meta
    m === nothing && error("No acquisition metadata loaded")
    if length(newLoop) != m.NAcq
        error("length of new array must equal NAcq: $(m.NAcq)")
    end

    new_vals = Int32.(newLoop)

    # Rebuild AcquisitionMeta with the replaced field
    fields = Dict{Symbol,Any}()
    for fname in fieldnames(AcquisitionMeta)
        fields[fname] = getfield(m, fname)
    end
    fields[Symbol(loop)] = new_vals
    s.meta = AcquisitionMeta((fields[f] for f in fieldnames(AcquisitionMeta))...)

    s.dims = nothing  # force recomputation
end

"""Drop all singleton dimensions from an array."""
function dropdims_all(A::AbstractArray)
    singleton_dims = Tuple(findall(size(A) .== 1))
    isempty(singleton_dims) && return A
    return dropdims(A; dims=singleton_dims)
end
