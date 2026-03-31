"""
    MDH

Measurement Data Header - stores parsed MDH fields from the binary twix data.
"""
mutable struct MDH
    ulPackBit::Vector{UInt8}
    ulPCI_rx::Vector{<:Integer}
    SlicePos::Matrix{Float32}
    aushIceProgramPara::Matrix{UInt16}
    aushFreePara::Matrix{UInt16}
    lMeasUID::Vector{UInt32}
    ulScanCounter::Vector{UInt32}
    ulTimeStamp::Vector{UInt32}
    ulPMUTimeStamp::Vector{UInt32}
    aulEvalInfoMask::Matrix{UInt32}
    ushSamplesInScan::Vector{UInt16}
    ushUsedChannels::Vector{UInt16}
    sLC::Matrix{UInt16}
    sCutOff::Matrix{UInt16}
    ushKSpaceCentreColumn::Vector{UInt16}
    ushCoilSelect::Vector{UInt16}
    fReadOutOffcentre::Vector{Float32}
    ulTimeSinceLastRF::Vector{UInt32}
    ushKSpaceCentreLineNo::Vector{UInt16}
    ushKSpaceCentrePartitionNo::Vector{UInt16}
end

"""
    MDHMask

Bitmask flags extracted from evalInfoMask, one per acquisition.
"""
mutable struct MDHMask
    MDH_ACQEND::Vector{UInt32}
    MDH_RTFEEDBACK::Vector{UInt32}
    MDH_HPFEEDBACK::Vector{UInt32}
    MDH_SYNCDATA::Vector{UInt32}
    MDH_RAWDATACORRECTION::Vector{UInt32}
    MDH_REFPHASESTABSCAN::Vector{UInt32}
    MDH_PHASESTABSCAN::Vector{UInt32}
    MDH_SIGNREV::Vector{UInt32}
    MDH_PHASCOR::Vector{UInt32}
    MDH_PATREFSCAN::Vector{UInt32}
    MDH_PATREFANDIMASCAN::Vector{UInt32}
    MDH_REFLECT::Vector{UInt32}
    MDH_NOISEADJSCAN::Vector{UInt32}
    MDH_VOP::Vector{UInt32}
    MDH_IMASCAN::Vector{UInt32}
end

"""
    FReadInfo

File reading parameters for channel header sizes and data shapes.
"""
mutable struct FReadInfo
    szScanHeader::Int
    szChannelHeader::Int
    iceParamSz::Int
    sz::Vector{Float64}
    shape::Vector{Float64}
    cut::Union{Nothing,Vector{Int}}
end

"""
    TwixMapObj

Main data object for one scan type (e.g. image, noise, refscan, etc.).
Stores MDH metadata and provides lazy data loading from the twix file.
"""
mutable struct TwixMapObj
    # Configuration
    dType::String
    fname::String
    softwareVersion::String
    rstrj::Union{Nothing,Vector{Float64}}

    # Options / flags
    ignoreROoffcenter::Bool
    removeOS::Bool
    regrid::Bool
    doAverage::Bool
    averageReps::Bool
    averageSets::Bool
    ignoreSeg::Bool
    squeeze_flag::Bool
    disableReflect::Bool
    skipToFirstLine::Bool
    average_dim::Vector{Bool}

    # Read info
    freadInfo::FReadInfo

    # MDH data (populated by readMDH!)
    NAcq::Int
    isBrokenFile::Bool

    NCol::Union{Nothing,Float64,Vector{Float64}}
    NCha::Union{Nothing,Float64,Vector{Float64}}
    Lin::Union{Nothing,Vector{Float64}}
    Ave::Union{Nothing,Vector{Float64}}
    Sli::Union{Nothing,Vector{Float64}}
    Par::Union{Nothing,Vector{Float64}}
    Eco::Union{Nothing,Vector{Float64}}
    Phs::Union{Nothing,Vector{Float64}}
    Rep::Union{Nothing,Vector{Float64}}
    Set::Union{Nothing,Vector{Float64}}
    Seg::Union{Nothing,Vector{Float64}}
    Ida::Union{Nothing,Vector{Float64}}
    Idb::Union{Nothing,Vector{Float64}}
    Idc::Union{Nothing,Vector{Float64}}
    Idd::Union{Nothing,Vector{Float64}}
    Ide::Union{Nothing,Vector{Float64}}

    centerCol::Union{Nothing,Vector{Float64}}
    centerLin::Union{Nothing,Vector{Float64}}
    centerPar::Union{Nothing,Vector{Float64}}
    cutOff::Union{Nothing,Matrix{Float64}}
    coilSelect::Union{Nothing,Vector{Float64}}
    ROoffcenter::Union{Nothing,Vector{Float64}}
    timeSinceRF::Union{Nothing,Vector{Float64}}
    IsReflected::Union{Nothing,Vector{Bool}}
    scancounter::Union{Nothing,Vector{Float64}}
    timestamp::Union{Nothing,Vector{Float64}}
    pmutime::Union{Nothing,Vector{Float64}}
    IsRawDataCorrect::Union{Nothing,Vector{Bool}}
    slicePos::Union{Nothing,Matrix{Float64}}
    iceParam::Union{Nothing,Matrix{Float64}}
    freeParam::Union{Nothing,Matrix{Float64}}

    memPos::Union{Nothing,Vector{Float64}}

    NLin::Union{Nothing,Float64}
    NPar::Union{Nothing,Float64}
    NSli::Union{Nothing,Float64}
    NAve_dim::Union{Nothing,Float64}
    NPhs::Union{Nothing,Float64}
    NEco::Union{Nothing,Float64}
    NRep::Union{Nothing,Float64}
    NSet::Union{Nothing,Float64}
    NSeg::Union{Nothing,Float64}
    NIda::Union{Nothing,Float64}
    NIdb::Union{Nothing,Float64}
    NIdc::Union{Nothing,Float64}
    NIdd::Union{Nothing,Float64}
    NIde::Union{Nothing,Float64}

    skipLin::Union{Nothing,Float64}
    skipPar::Union{Nothing,Float64}
    full_size::Union{Nothing,Vector{Float64}}
end

# Dimension names in order
const DATA_DIMS = ["Col", "Cha", "Lin", "Par", "Sli", "Ave", "Phs",
                   "Eco", "Rep", "Set", "Seg", "Ida", "Idb", "Idc", "Idd", "Ide"]

"""
    TwixMapObj(dataType, fname, version, rstraj; kwargs...)

Construct a TwixMapObj for a given data type.
"""
function TwixMapObj(dataType::String, fname::String, version::String,
                    rstraj=nothing; kwargs...)
    dType = lowercase(dataType)

    ignoreROoffcenter = get(kwargs, :ignoreROoffcenter, false)
    removeOS = get(kwargs, :removeOS, true)
    regrid_flag = get(kwargs, :regrid, true)
    doAverage = get(kwargs, :doAverage, false)
    averageReps = get(kwargs, :averageReps, false)
    averageSets = get(kwargs, :averageSets, false)
    ignoreSeg = get(kwargs, :ignoreSeg, false)
    squeeze_flag = get(kwargs, :squeeze, false)
    disableReflect = get(kwargs, :disableReflect, false)

    if version == "vb"
        fri = FReadInfo(0, 128, 4, zeros(2), zeros(2), nothing)
    elseif version == "vd"
        fri = FReadInfo(192, 32, 24, zeros(2), zeros(2), nothing)
    else
        error("Software version '$version' not supported")
    end

    if rstraj === nothing
        regrid_flag = false
    end

    average_dim = fill(false, 16)
    ave_ix = findfirst(==("Ave"), DATA_DIMS)
    rep_ix = findfirst(==("Rep"), DATA_DIMS)
    set_ix = findfirst(==("Set"), DATA_DIMS)
    seg_ix = findfirst(==("Seg"), DATA_DIMS)
    average_dim[ave_ix] = doAverage
    average_dim[rep_ix] = averageReps
    average_dim[set_ix] = averageSets
    average_dim[seg_ix] = ignoreSeg

    skipToFirstLine = !(dType == "image" || dType == "phasestab")

    TwixMapObj(
        dType, fname, version,
        rstraj === nothing ? nothing : Float64.(rstraj),
        ignoreROoffcenter, removeOS, regrid_flag, doAverage, averageReps,
        averageSets, ignoreSeg, squeeze_flag, disableReflect, skipToFirstLine,
        average_dim,
        fri,
        0, false,  # NAcq, isBrokenFile
        # NCol..Ide
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        nothing, nothing,
        # centerCol..freeParam (15 fields: centerCol, centerLin, centerPar, cutOff, coilSelect, ROoffcenter, timeSinceRF, IsReflected, scancounter, timestamp, pmutime, IsRawDataCorrect, slicePos, iceParam, freeParam)
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        nothing,
        # memPos
        nothing,
        # NLin..NIde
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        nothing, nothing, nothing, nothing, nothing, nothing, nothing,
        # skipLin, skipPar, full_size
        nothing, nothing, nothing
    )
end

# --- Properties ---

function fullSize(obj::TwixMapObj)
    if obj.full_size === nothing
        clean!(obj)
    end
    return obj.full_size
end

function dataSize(obj::TwixMapObj)
    out = copy(fullSize(obj))

    if obj.removeOS
        ix = findfirst(==("Col"), DATA_DIMS)
        out[ix] = obj.NCol / 2
    end

    if obj.average_dim[1] || obj.average_dim[2]
        println("averaging in col and cha dim not supported, resetting flag")
        obj.average_dim[1] = false
        obj.average_dim[2] = false
    end

    for i in 1:length(out)
        if obj.average_dim[i]
            out[i] = 1
        end
    end
    return out
end

function sqzSize(obj::TwixMapObj)
    ds = dataSize(obj)
    return Int.(ds[ds .> 1])
end

function sqzDims(obj::TwixMapObj)
    ds = dataSize(obj)
    return DATA_DIMS[ds .> 1]
end

# --- Flag properties ---

function set_flagRemoveOS!(obj::TwixMapObj, val::Bool)
    obj.removeOS = val
end

function set_flagRampSampRegrid!(obj::TwixMapObj, val::Bool)
    if val && obj.rstrj === nothing
        error("No trajectory for regridding available")
    end
    obj.regrid = val
end

function set_flagDoAverage!(obj::TwixMapObj, val::Bool)
    ix = findfirst(==("Ave"), DATA_DIMS)
    obj.average_dim[ix] = val
end

function set_flagAverageReps!(obj::TwixMapObj, val::Bool)
    ix = findfirst(==("Rep"), DATA_DIMS)
    obj.average_dim[ix] = val
end

function set_flagAverageSets!(obj::TwixMapObj, val::Bool)
    ix = findfirst(==("Set"), DATA_DIMS)
    obj.average_dim[ix] = val
end

function set_flagIgnoreSeg!(obj::TwixMapObj, val::Bool)
    ix = findfirst(==("Seg"), DATA_DIMS)
    obj.average_dim[ix] = val
end

function set_flagSkipToFirstLine!(obj::TwixMapObj, val::Bool)
    if val != obj.skipToFirstLine
        obj.skipToFirstLine = val
        if val
            obj.skipLin = minimum(obj.Lin)
            obj.skipPar = minimum(obj.Par)
        else
            obj.skipLin = 0.0
            obj.skipPar = 0.0
        end
        obj.full_size[3] = max(1.0, obj.NLin - obj.skipLin)
        obj.full_size[4] = max(1.0, obj.NPar - obj.skipPar)
    end
end

function set_flagDisableReflect!(obj::TwixMapObj, val::Bool)
    obj.disableReflect = val
end

# --- Property getters for Python-compatible field access ---

function Base.getproperty(obj::TwixMapObj, name::Symbol)
    if name === :flagRemoveOS
        return obj.removeOS
    elseif name === :flagRampSampRegrid
        return obj.regrid
    elseif name === :flagDoAverage
        ix = findfirst(==("Ave"), DATA_DIMS)
        return getfield(obj, :average_dim)[ix]
    elseif name === :flagIgnoreSeg
        ix = findfirst(==("Seg"), DATA_DIMS)
        return getfield(obj, :average_dim)[ix]
    elseif name === :flagSkipToFirstLine
        return getfield(obj, :skipToFirstLine)
    elseif name === :flagDisableReflect
        return getfield(obj, :disableReflect)
    elseif name === :flagAverageReps
        ix = findfirst(==("Rep"), DATA_DIMS)
        return getfield(obj, :average_dim)[ix]
    elseif name === :flagAverageSets
        ix = findfirst(==("Set"), DATA_DIMS)
        return getfield(obj, :average_dim)[ix]
    else
        return getfield(obj, name)
    end
end

function Base.setproperty!(obj::TwixMapObj, name::Symbol, val)
    if name === :flagRemoveOS
        set_flagRemoveOS!(obj, val)
    elseif name === :flagRampSampRegrid
        set_flagRampSampRegrid!(obj, val)
    elseif name === :flagDoAverage
        set_flagDoAverage!(obj, val)
    elseif name === :flagIgnoreSeg
        set_flagIgnoreSeg!(obj, val)
    elseif name === :flagSkipToFirstLine
        set_flagSkipToFirstLine!(obj, val)
    elseif name === :flagDisableReflect
        set_flagDisableReflect!(obj, val)
    elseif name === :flagAverageReps
        set_flagAverageReps!(obj, val)
    elseif name === :flagAverageSets
        set_flagAverageSets!(obj, val)
    elseif name === :squeeze
        setfield!(obj, :squeeze_flag, val)
    else
        setfield!(obj, name, val)
    end
end

function Base.show(io::IO, obj::TwixMapObj)
    fs = fullSize(obj)
    println(io, "***twix_map_obj***")
    println(io, "File: $(obj.fname)")
    println(io, "Software: $(obj.softwareVersion)")
    println(io, "Number of acquisitions read $(obj.NAcq)")
    println(io, "Data size is $fs")
    println(io, "Squeezed data size is $(sqzSize(obj)) ($(sqzDims(obj)))")
    @printf(io, "NCol = %.0f\n", obj.NCol)
    @printf(io, "NCha = %.0f\n", obj.NCha)
    @printf(io, "NLin  = %.0f\n", obj.NLin)
    @printf(io, "NAve  = %.0f\n", obj.NAve_dim)
    @printf(io, "NSli  = %.0f\n", obj.NSli)
    @printf(io, "NPar  = %.0f\n", obj.NPar)
    @printf(io, "NEco  = %.0f\n", obj.NEco)
    @printf(io, "NPhs  = %.0f\n", obj.NPhs)
    @printf(io, "NRep  = %.0f\n", obj.NRep)
    @printf(io, "NSet  = %.0f\n", obj.NSet)
    @printf(io, "NSeg  = %.0f\n", obj.NSeg)
    @printf(io, "NIda  = %.0f\n", obj.NIda)
    @printf(io, "NIdb  = %.0f\n", obj.NIdb)
    @printf(io, "NIdc  = %.0f\n", obj.NIdc)
    @printf(io, "NIdd  = %.0f\n", obj.NIdd)
    @printf(io, "NIde  = %.0f",   obj.NIde)
end

"""
    readMDH!(obj::TwixMapObj, mdh::MDH, filePos, useScan)

Extract MDH values for the selected scans and populate the object fields.
"""
function readMDH!(obj::TwixMapObj, mdh::MDH, filePos::Vector{Float64}, useScan::AbstractVector{Bool})
    obj.NAcq = sum(useScan)
    sLC = Float64.(mdh.sLC)
    evalInfoMask1 = mdh.aulEvalInfoMask[useScan, 1]

    obj.NCol = Float64.(mdh.ushSamplesInScan[useScan])
    obj.NCha = Float64.(mdh.ushUsedChannels[useScan])
    obj.Lin = sLC[useScan, 1]
    obj.Ave = sLC[useScan, 2]
    obj.Sli = sLC[useScan, 3]
    obj.Par = sLC[useScan, 4]
    obj.Eco = sLC[useScan, 5]
    obj.Phs = sLC[useScan, 6]
    obj.Rep = sLC[useScan, 7]
    obj.Set = sLC[useScan, 8]
    obj.Seg = sLC[useScan, 9]
    obj.Ida = sLC[useScan, 10]
    obj.Idb = sLC[useScan, 11]
    obj.Idc = sLC[useScan, 12]
    obj.Idd = sLC[useScan, 13]
    obj.Ide = sLC[useScan, 14]

    obj.centerCol = Float64.(mdh.ushKSpaceCentreColumn[useScan])
    obj.centerLin = Float64.(mdh.ushKSpaceCentreLineNo[useScan])
    obj.centerPar = Float64.(mdh.ushKSpaceCentrePartitionNo[useScan])
    obj.cutOff = Float64.(mdh.sCutOff[useScan, :])
    obj.coilSelect = Float64.(mdh.ushCoilSelect[useScan])
    obj.ROoffcenter = Float64.(mdh.fReadOutOffcentre[useScan])
    obj.timeSinceRF = Float64.(mdh.ulTimeSinceLastRF[useScan])
    obj.IsReflected = Vector{Bool}(min.(evalInfoMask1 .& UInt32(2^24), UInt32(1)))
    obj.scancounter = Float64.(mdh.ulScanCounter[useScan])
    obj.timestamp = Float64.(mdh.ulTimeStamp[useScan])
    obj.pmutime = Float64.(mdh.ulPMUTimeStamp[useScan])
    obj.IsRawDataCorrect = Vector{Bool}(min.(evalInfoMask1 .& UInt32(2^10), UInt32(1)))
    obj.slicePos = Float64.(mdh.SlicePos[useScan, :])
    obj.iceParam = Float64.(mdh.aushIceProgramPara[useScan, :])
    obj.freeParam = Float64.(mdh.aushFreePara[useScan, :])

    obj.memPos = filePos[useScan]
end

"""
    tryAndFixLastMdh!(obj::TwixMapObj)

Attempt to recover from read errors by trimming the last acquisition.
"""
function tryAndFixLastMdh!(obj::TwixMapObj)
    isLastAcqGood = false
    cnt = 0

    while !isLastAcqGood && obj.NAcq > 0 && cnt < 100
        try
            unsorted(obj, obj.NAcq)
            isLastAcqGood = true
        catch e
            @warn "Error fixing last MDH. NAcq = $(obj.NAcq)" exception=e
            obj.isBrokenFile = true
            obj.NAcq -= 1
        end
        cnt += 1
    end
end

"""
    clean!(obj::TwixMapObj)

Finalize MDH data: compute dimension sizes and file read parameters.
"""
function clean!(obj::TwixMapObj)
    if obj.NAcq == 0
        return
    end

    obj.NLin = maximum(obj.Lin) + 1
    obj.NPar = maximum(obj.Par) + 1
    obj.NSli = maximum(obj.Sli) + 1
    obj.NAve_dim = maximum(obj.Ave) + 1
    obj.NPhs = maximum(obj.Phs) + 1
    obj.NEco = maximum(obj.Eco) + 1
    obj.NRep = maximum(obj.Rep) + 1
    obj.NSet = maximum(obj.Set) + 1
    obj.NSeg = maximum(obj.Seg) + 1
    obj.NIda = maximum(obj.Ida) + 1
    obj.NIdb = maximum(obj.Idb) + 1
    obj.NIdc = maximum(obj.Idc) + 1
    obj.NIdd = maximum(obj.Idd) + 1
    obj.NIde = maximum(obj.Ide) + 1

    # Assume all NCol and NCha are the same
    if obj.NCol isa AbstractVector
        obj.NCol = obj.NCol[1]
    end
    if obj.NCha isa AbstractVector
        obj.NCha = obj.NCha[1]
    end

    if obj.dType == "refscan"
        if obj.NLin > 65500
            minLin = minimum(obj.Lin[obj.Lin .> 65500])
            obj.Lin = mod.(obj.Lin .+ (65536 - minLin), 65536)
            obj.NLin = maximum(obj.Lin)
        end
        if obj.NPar > 65500
            minPar = minimum(obj.Par[obj.Par .> 65500])
            obj.Par = mod.(obj.Par .+ (65536 - minPar), 65536)
            obj.NPar = maximum(obj.Par)
        end
    end

    if !obj.skipToFirstLine
        obj.skipLin = 0.0
        obj.skipPar = 0.0
    else
        obj.skipLin = minimum(obj.Lin)
        obj.skipPar = minimum(obj.Par)
    end

    NLinAlloc = max(1.0, obj.NLin - obj.skipLin)
    NParAlloc = max(1.0, obj.NPar - obj.skipPar)

    obj.full_size = Float64[
        obj.NCol, obj.NCha, NLinAlloc, NParAlloc,
        obj.NSli, obj.NAve_dim, obj.NPhs, obj.NEco,
        obj.NRep, obj.NSet, obj.NSeg, obj.NIda,
        obj.NIdb, obj.NIdc, obj.NIdd, obj.NIde
    ]

    nByte = obj.NCha * (obj.freadInfo.szChannelHeader + 8 * obj.NCol)

    obj.freadInfo.sz = [2.0, nByte / 8.0]
    obj.freadInfo.shape = [obj.NCol + obj.freadInfo.szChannelHeader / 8.0, obj.NCha]
    obj.freadInfo.cut = Int.(obj.freadInfo.szChannelHeader / 8.0) .+ collect(1:Int(obj.NCol))
end

"""
    calcIndices(obj::TwixMapObj)

Calculate the mapping from MDH acquisitions to target array positions.
Returns (ixToRaw, ixToTarget).
"""
function calcIndices(obj::TwixMapObj)
    LinIx = obj.Lin .- obj.skipLin
    ParIx = obj.Par .- obj.skipPar
    fs = fullSize(obj)
    sz = Int.(fs[3:end])

    n = length(LinIx)
    ixToTarget = zeros(Int, n)

    for i in 1:n
        # Build multi-index (1-based for Julia)
        mi = (
            Int(LinIx[i]) + 1,
            Int(ParIx[i]) + 1,
            Int(obj.Sli[i]) + 1,
            Int(obj.Ave[i]) + 1,
            Int(obj.Phs[i]) + 1,
            Int(obj.Eco[i]) + 1,
            Int(obj.Rep[i]) + 1,
            Int(obj.Set[i]) + 1,
            Int(obj.Seg[i]) + 1,
            Int(obj.Ida[i]) + 1,
            Int(obj.Idb[i]) + 1,
            Int(obj.Idc[i]) + 1,
            Int(obj.Idd[i]) + 1,
            Int(obj.Ide[i]) + 1
        )
        # Linear index (1-based)
        li = LinearIndices(Tuple(sz))
        ixToTarget[i] = li[mi...]
    end

    # Inverse: target -> raw
    total = prod(sz)
    ixToRaw = zeros(Int, total)  # 0 means not acquired

    for (i, itt) in enumerate(ixToTarget)
        ixToRaw[itt] = i
    end

    return ixToRaw, ixToTarget
end

"""
    calcRange(obj::TwixMapObj, S)

Calculate selection ranges for data retrieval. Returns (selRange, selRangeSz, outSize).
"""
function calcRange(obj::TwixMapObj, S)
    clean!(obj)
    ds = dataSize(obj)
    ndims_data = length(ds)

    selRange = [collect(1:Int(ds[k])) for k in 1:ndims_data]
    outSize = ones(Int, ndims_data)

    bSqueeze = obj.squeeze_flag

    if S === nothing || S === Colon()
        # Select all data
        for k in 1:ndims_data
            selRange[k] = collect(1:Int(ds[k]))
        end
        if !bSqueeze
            outSize = Int.(ds)
        else
            outSize = sqzSize(obj)
        end
    else
        # S is a tuple of ranges/indices
        for (k, s) in enumerate(S)
            if !bSqueeze
                cDim = k
            else
                sd = sqzDims(obj)
                cDim = findfirst(==(sd[k]), DATA_DIMS)
            end

            if s === Colon()
                if k < length(S)
                    selRange[cDim] = collect(1:Int(ds[cDim]))
                else
                    for ll in cDim:ndims_data
                        selRange[ll] = collect(1:Int(ds[ll]))
                    end
                    outSize[k] = Int(prod(ds[cDim:end]))
                    break
                end
            elseif s isa UnitRange || s isa StepRange
                selRange[cDim] = collect(s)
            elseif s isa Integer
                selRange[cDim] = [s]
            else
                selRange[cDim] = collect(s)
            end

            outSize[k] = length(selRange[cDim])
        end
    end

    selRangeSz = [length(r) for r in selRange]

    # Select all indices for averaged dims
    for iDx in 1:ndims_data
        if obj.average_dim[iDx]
            clean!(obj)
            fs = fullSize(obj)
            selRange[iDx] = collect(1:Int(fs[iDx]))
        end
    end

    return selRange, selRangeSz, outSize
end

"""
    unsorted(obj::TwixMapObj, ival=nothing)

Return unsorted data [NCol, NCha, #samples].
"""
function unsorted(obj::TwixMapObj, ival=nothing)
    if ival !== nothing
        mem = [obj.memPos[ival]]
    else
        mem = obj.memPos
    end
    return readData(obj, mem)
end

"""
    readData(obj, mem; cIxToTarg, cIxToRaw, selRange, selRangeSz, outSize)

Read raw data from file. Core I/O routine.
"""
function readData(obj::TwixMapObj, mem::AbstractVector{Float64};
                  cIxToTarg=nothing, cIxToRaw=nothing,
                  selRange=nothing, selRangeSz=nothing, outSize=nothing)

    mem_i64 = Int64.(mem)
    ds = dataSize(obj)

    if outSize === nothing
        if selRange === nothing
            selRange = [collect(1:Int(ds[1])), collect(1:Int(ds[2]))]
        else
            selRange[1] = collect(1:Int(ds[1]))
            selRange[2] = collect(1:Int(ds[2]))
        end

        outSize = vcat(Int.(ds[1:2]), [length(mem_i64)])
        selRangeSz = copy(outSize)
        cIxToTarg = collect(1:selRangeSz[3])
        cIxToRaw = copy(cIxToTarg)
    end

    out = zeros(ComplexF32, Tuple(outSize))
    out = reshape(out, selRangeSz[1], selRangeSz[2], :)

    szScanHeader = obj.freadInfo.szScanHeader
    readSize = Int64.(obj.freadInfo.sz)
    readShape = Int64.(obj.freadInfo.shape)
    readCut = obj.freadInfo.cut

    NCol_int = Int64(obj.NCol)
    keepOS = vcat(collect(1:div(NCol_int, 4)), collect(3*div(NCol_int, 4)+1:NCol_int))

    bIsReflected = obj.IsReflected[cIxToRaw]
    bRegrid = obj.regrid && obj.rstrj !== nothing && length(obj.rstrj) > 1

    ro_shift = obj.ROoffcenter[cIxToRaw] .* Float64(!obj.ignoreROoffcenter)
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
    trgTrj = nothing
    if bRegrid
        rsTrj = obj.rstrj
        trgTrj_x = range(minimum(rsTrj), maximum(rsTrj), length=NCol_int)
    end

    count_ave = zeros(Float32, 1, 1, size(out, 3))
    kMax = length(mem_i64)

    fid = open(obj.fname, "r")

    p = Progress(kMax, desc="read data ", enabled=true)

    for k in 1:kMax
        seek(fid, mem_i64[k] + szScanHeader)
        raw_floats = Vector{Float32}(undef, prod(readSize))
        read!(fid, raw_floats)

        raw_mat = reshape(raw_floats, readSize[1], readSize[2])

        raw_complex = try
            complex_raw = raw_mat[1, :] .+ im .* raw_mat[2, :]
            reshape(complex_raw, readShape[1], readShape[2])
        catch
            @warn "Unexpected read error at byte offset $(mem_i64[k] + szScanHeader)"
            fill(ComplexF32(-Inf), readShape[1], readShape[2])
        end

        block[:, :, blockCtr + 1] = raw_complex
        blockCtr += 1

        if (blockCtr == blockSz) || (k == kMax) || (isBrokenRead && blockCtr > 1)
            tic = time()

            # Remove MDH/channel header data
            blk = block[readCut, :, 1:blockCtr]

            ix = (k - blockCtr + 1):k

            # Reflect
            if !obj.disableReflect
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

                # Regrid each channel/block using interpolation
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
            if obj.removeOS
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
                    blockSz = max(div(blockSz, 2), 1)
                    blockInit = blockInit[:, :, 1:blockSz]
                    doLockblockSz = true
                end
                tprev = t
            end

            blockCtr = 0
            block = copy(blockInit)
        end

        if isBrokenRead
            obj.isBrokenFile = true
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

    if obj.squeeze_flag
        return dropdims_all(out)
    else
        return out
    end
end

"""
    getdata(obj::TwixMapObj; key=nothing)

Retrieve data from the TwixMapObj, equivalent to Python's `obj['']` or `obj[:]`.
Pass `key=nothing` for all data, or a tuple of ranges for slicing.
"""
function getdata(obj::TwixMapObj; key=nothing)
    selRange, selRangeSz, outSize = calcRange(obj, key)

    ixToRaw, _ = calcIndices(obj)

    fs = fullSize(obj)
    sz = Int.(fs[3:end])

    # Build selection from target space
    tmp = reshape(collect(1:prod(sz)), Tuple(sz))
    for (i, ids) in enumerate(selRange[3:end])
        dims_to_select = ntuple(j -> j == i ? ids : (1:size(tmp, j)), ndims(tmp))
        tmp = tmp[dims_to_select...]
    end

    ixToRaw_sel = ixToRaw[tmp[:]]
    ixToRaw_sel = ixToRaw_sel[ixToRaw_sel .> 0]

    # Calculate ixToTarg for the selected range
    cIx = zeros(Int, 14, length(ixToRaw_sel))
    dim_fields = [:Lin, :Par, :Sli, :Ave, :Phs, :Eco, :Rep, :Set, :Seg, :Ida, :Idb, :Idc, :Idd, :Ide]
    skip_fields = [obj.skipLin, obj.skipPar, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for (di, (field, skip)) in enumerate(zip(dim_fields, skip_fields))
        if !obj.average_dim[di + 2]
            vals = getfield(obj, field)
            cIx[di, :] = Int.(vals[ixToRaw_sel] .- skip) .+ 1  # 1-based
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

    szz = selRangeSz[3:end]
    ixToTarg = zeros(Int, size(cIx, 2))
    li = LinearIndices(Tuple(szz))
    for i in 1:length(ixToTarg)
        idx = ntuple(j -> cIx[j, i], 14)
        ixToTarg[i] = li[idx...]
    end

    mem = obj.memPos[ixToRaw_sel]
    ix_sort = sortperm(mem)
    mem = mem[ix_sort]
    ixToTarg = ixToTarg[ix_sort]
    ixToRaw_sel = ixToRaw_sel[ix_sort]

    return readData(obj, mem; cIxToTarg=ixToTarg, cIxToRaw=ixToRaw_sel,
                    selRange=selRange, selRangeSz=selRangeSz, outSize=outSize)
end

# Allow obj[:] syntax via getindex
function Base.getindex(obj::TwixMapObj, args...)
    # Convert Julia 1-based ranges to internal format
    getdata(obj; key=args)
end

"""
    fixLoopCounter!(obj, loop::String, newLoop::Vector)

Replace a loop counter (e.g., "Ave") with new values.
"""
function fixLoopCounter!(obj::TwixMapObj, loop::String, newLoop::Vector)
    if length(newLoop) != obj.NAcq
        error("length of new array must equal NAcq: $(obj.NAcq)")
    end
    setfield!(obj, Symbol(loop), Float64.(newLoop))
    N = maximum(newLoop)
    setfield!(obj, Symbol("N" * loop), N)
    fs = fullSize(obj)
    ix = findfirst(==(loop), DATA_DIMS)
    fs[ix] = N
    obj.full_size = fs
end

# Utility
function dropdims_all(A::AbstractArray)
    singleton_dims = Tuple(findall(size(A) .== 1))
    if isempty(singleton_dims)
        return A
    end
    return dropdims(A; dims=singleton_dims)
end