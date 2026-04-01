

# ─── File Read Info ────────────────────────────────────────────────────

"""
    ReadInfo

Binary layout parameters for reading channel data from a twix file.
Determined by software version (VB vs VD).
"""
struct ReadInfo
    szScanHeader::Int
    szChannelHeader::Int
    iceParamSz::Int
end

ReadInfo(version::String) = if version == "vb"
    ReadInfo(0, VB_CHANNEL_HEADER_SIZE, 4)
elseif version == "vd"
    ReadInfo(VD_SCAN_HEADER_SIZE, VD_CHANNEL_HEADER_SIZE, 24)
else
    error("Software version '$version' not supported")
end

# ─── Per-Acquisition Metadata ──────────────────────────────────────────

"""
    AcquisitionMeta

Per-acquisition metadata extracted from MDH headers.
All loop counters are stored as Int32; positions as Float32.
Populated by `readMDH!`.
"""
struct AcquisitionMeta
    NAcq::Int

    # Loop counters (0-based values from MDH, length = NAcq)
    Lin::Vector{Int32}
    Par::Vector{Int32}
    Sli::Vector{Int32}
    Ave::Vector{Int32}
    Phs::Vector{Int32}
    Eco::Vector{Int32}
    Rep::Vector{Int32}
    Set::Vector{Int32}
    Seg::Vector{Int32}
    Ida::Vector{Int32}
    Idb::Vector{Int32}
    Idc::Vector{Int32}
    Idd::Vector{Int32}
    Ide::Vector{Int32}

    # K-space / coil metadata
    centerCol::Vector{Int32}
    centerLin::Vector{Int32}
    centerPar::Vector{Int32}
    cutOff::Matrix{Int32}
    coilSelect::Vector{Int32}
    ROoffcenter::Vector{Float32}
    timeSinceRF::Vector{UInt32}
    IsReflected::BitVector
    IsRawDataCorrect::BitVector
    scancounter::Vector{UInt32}
    timestamp::Vector{UInt32}
    pmutime::Vector{UInt32}
    slicePos::Matrix{Float32}
    iceParam::Matrix{UInt16}
    freeParam::Matrix{UInt16}

    # File positions for lazy reading
    memPos::Vector{Int64}

    # NCol and NCha (uniform across acquisitions)
    NCol::Int
    NCha::Int
end

"""
    loop_counter(meta::AcquisitionMeta, dim_index::Int) -> Vector{Int32}

Get the loop counter vector for a given dimension index (DIM_LIN..DIM_IDE).
"""
function loop_counter(meta::AcquisitionMeta, dim::Int)
    dim == DIM_LIN && return meta.Lin
    dim == DIM_PAR && return meta.Par
    dim == DIM_SLI && return meta.Sli
    dim == DIM_AVE && return meta.Ave
    dim == DIM_PHS && return meta.Phs
    dim == DIM_ECO && return meta.Eco
    dim == DIM_REP && return meta.Rep
    dim == DIM_SET && return meta.Set
    dim == DIM_SEG && return meta.Seg
    dim == DIM_IDA && return meta.Ida
    dim == DIM_IDB && return meta.Idb
    dim == DIM_IDC && return meta.Idc
    dim == DIM_IDD && return meta.Idd
    dim == DIM_IDE && return meta.Ide
    error("Invalid dimension index: $dim")
end

# ─── Computed Dimension Sizes ──────────────────────────────────────────

"""
    DimSizes

Computed dimension extents and skip offsets, all as concrete `Int`.
Immutable — recomputed when flags change.
"""
struct DimSizes
    NCol::Int
    NCha::Int
    NLin::Int
    NPar::Int
    NSli::Int
    NAve::Int
    NPhs::Int
    NEco::Int
    NRep::Int
    NSet::Int
    NSeg::Int
    NIda::Int
    NIdb::Int
    NIdc::Int
    NIdd::Int
    NIde::Int
    skipLin::Int
    skipPar::Int
end

"""
    dim_extent(dims::DimSizes, i::Int) -> Int

Get the extent for dimension `i` (1-based, matching DIM_* constants).
"""
function dim_extent(d::DimSizes, i::Int)
    i == DIM_COL && return d.NCol
    i == DIM_CHA && return d.NCha
    i == DIM_LIN && return d.NLin
    i == DIM_PAR && return d.NPar
    i == DIM_SLI && return d.NSli
    i == DIM_AVE && return d.NAve
    i == DIM_PHS && return d.NPhs
    i == DIM_ECO && return d.NEco
    i == DIM_REP && return d.NRep
    i == DIM_SET && return d.NSet
    i == DIM_SEG && return d.NSeg
    i == DIM_IDA && return d.NIda
    i == DIM_IDB && return d.NIdb
    i == DIM_IDC && return d.NIdc
    i == DIM_IDD && return d.NIdd
    i == DIM_IDE && return d.NIde
    error("Invalid dimension index: $i")
end

# ─── ScanData (replaces TwixMapObj) ───────────────────────────────────

"""
    ScanData

Main data object for one scan type (image, noise, refscan, etc.).
Stores MDH metadata and provides lazy data loading from the twix file.

Replaces the old `TwixMapObj` with a cleaner, type-stable design:
- `flags`: mutable processing flags
- `meta`: per-acquisition metadata (Nothing until MDH is read)
- `dims`: computed dimension sizes (Nothing until `compute_dims!` is called)
"""
mutable struct ScanData
    # Identity
    dType::String
    fname::String
    version::String
    rstrj::Union{Nothing,Vector{Float64}}

    # Read layout (determined by software version)
    readinfo::ReadInfo

    # Processing flags (all default to false = no processing)
    removeOS::Bool
    regrid::Bool
    doAverage::Bool
    averageReps::Bool
    averageSets::Bool
    ignoreSeg::Bool
    squeeze::Bool
    disableReflect::Bool
    skipToFirstLine::Bool
    ignoreROoffcenter::Bool

    # State (populated during read)
    meta::Union{Nothing,AcquisitionMeta}
    dims::Union{Nothing,DimSizes}
    isBrokenFile::Bool
end

"""
    ScanData(dataType, fname, version, rstraj=nothing; kwargs...)

Construct a `ScanData` for a given scan type.
"""
function ScanData(dataType::String, fname::String, version::String,
                  rstraj=nothing;
                  removeOS::Bool          = false,
                  regrid::Bool            = false,
                  doAverage::Bool         = false,
                  averageReps::Bool       = false,
                  averageSets::Bool       = false,
                  ignoreSeg::Bool         = false,
                  squeeze::Bool           = false,
                  disableReflect::Bool    = false,
                  skipToFirstLine::Union{Bool,Nothing} = nothing,
                  ignoreROoffcenter::Bool = false)
    dType = lowercase(dataType)

    # Can't regrid without a trajectory
    regrid = regrid && rstraj !== nothing

    # Non-image scans skip to first acquired line by default
    if skipToFirstLine === nothing
        skipToFirstLine = !(dType == "image" || dType == "phasestab")
    end

    ri = ReadInfo(version)

    ScanData(dType, fname, version,
             rstraj === nothing ? nothing : Float64.(rstraj),
             ri,
             removeOS, regrid, doAverage, averageReps, averageSets,
             ignoreSeg, squeeze, disableReflect, skipToFirstLine,
             ignoreROoffcenter,
             nothing, nothing, false)
end

"""
    average_dim(s::ScanData) -> Vector{Bool}

Return a length-16 boolean vector indicating which dimensions are averaged.
"""
function average_dim(s::ScanData)
    v = fill(false, N_DIMS)
    v[DIM_AVE] = s.doAverage
    v[DIM_REP] = s.averageReps
    v[DIM_SET] = s.averageSets
    v[DIM_SEG] = s.ignoreSeg
    return v
end

# ─── TwixObj (top-level result container) ──────────────────────────────

"""
    TwixObj

Result object from `mapVBVD`. Contains header and scan data objects
accessible via attribute-style access (e.g., `obj.image`, `obj.hdr`).
"""
mutable struct TwixObj
    _data::Dict{String,Any}
end

TwixObj() = TwixObj(Dict{String,Any}())

Base.getindex(t::TwixObj, key::String) = getfield(t, :_data)[key]
Base.setindex!(t::TwixObj, value, key::String) = (getfield(t, :_data)[key] = value)
Base.haskey(t::TwixObj, key::String) = haskey(getfield(t, :_data), key)
Base.keys(t::TwixObj) = keys(getfield(t, :_data))
Base.delete!(t::TwixObj, key::String) = delete!(getfield(t, :_data), key)
Base.pop!(t::TwixObj, key::String, default=nothing) = pop!(getfield(t, :_data), key, default)

# Type-annotated helper: narrows return to Union{TwixHdr,ScanData}
# so the REPL can infer propertynames for chained tab-completion.
_twixobj_val(t::TwixObj, key::String)::Union{TwixHdr, ScanData} = getfield(t, :_data)[key]

function Base.getproperty(t::TwixObj, name::Symbol)
    name === :_data && return getfield(t, :_data)
    key = String(name)
    d = getfield(t, :_data)
    haskey(d, key) && return _twixobj_val(t, key)
    error("TwixObj has no field '$key'. Available: $(sort(collect(keys(d))))")
end

function Base.setproperty!(t::TwixObj, name::Symbol, val)
    name === :_data && return setfield!(t, :_data, val)
    getfield(t, :_data)[String(name)] = val
end

function Base.propertynames(t::TwixObj, private::Bool=false)
    syms = Symbol[]
    for k in keys(t._data)
        if k isa String && !isempty(k)
            push!(syms, Symbol(k))
        end
    end
    sort!(syms)
    return syms
end

function Base.show(io::IO, t::TwixObj)
    ks = sort(collect(keys(t._data)))
    scan_keys = filter(k -> k != "hdr", ks)
    print(io, "TwixObj with ", length(scan_keys), " scan type(s): ", join(scan_keys, ", "))
end

function Base.show(io::IO, ::MIME"text/plain", t::TwixObj)
    ks = sort(collect(keys(t._data)))
    scan_keys = filter(k -> k != "hdr", ks)
    println(io, "TwixObj")
    if haskey(t._data, "hdr")
        println(io, "  📋 hdr")
    end
    for k in scan_keys
        v = t._data[k]
        if v isa ScanData && v.meta !== nothing
            println(io, "  📊 ", k, " (", v.meta.NAcq, " acq, size ", sqzSize(v), ")")
        elseif v isa ScanData
            println(io, "  📊 ", k, " [no data]")
        else
            println(io, "  ", k)
        end
    end
end

# ─── MDH binary structures ────────────────────────────────────────────

"""
    MDH

Measurement Data Header — stores parsed MDH fields from binary twix data.
"""
struct MDH
    ulPackBit::Vector{UInt8}
    ulPCI_rx::Vector{Int16}
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
struct MDHMask
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

# ─── Header type ───────────────────────────────────────────────────────

"""
    TwixHdr

Header object for Siemens twix files. Wraps a `NestedDict` with top-level
sections (e.g., "Meas", "MeasYaps", "Phoenix") each containing parsed
ASCCONV and XProtocol data as nested trees.

# Access patterns
```julia
hdr.MeasYaps.sKSpace.lBaseResolution  # dot-access with tab-completion
hdr["MeasYaps.sKSpace.lBaseResolution"]  # path string
search(hdr, "lBaseRes")                  # search all paths
```
"""
struct TwixHdr
    data::NestedDict
end

TwixHdr() = TwixHdr(NestedDict())










# Forward dict interface to inner NestedDict (use getfield to avoid getproperty dispatch)
Base.getindex(h::TwixHdr, key) = getfield(h, :data)[key]
Base.setindex!(h::TwixHdr, value, key::AbstractString) = (getfield(h, :data)[String(key)] = value)
Base.haskey(h::TwixHdr, key::AbstractString) = haskey(getfield(h, :data), String(key))
Base.keys(h::TwixHdr) = keys(getfield(h, :data))
Base.values(h::TwixHdr) = values(getfield(h, :data))
Base.iterate(h::TwixHdr) = iterate(getfield(h, :data))
Base.iterate(h::TwixHdr, state) = iterate(getfield(h, :data), state)
Base.length(h::TwixHdr) = length(getfield(h, :data))

function Base.getproperty(h::TwixHdr, name::Symbol)
    name === :data && return getfield(h, :data)
    key = String(name)
    nd = getfield(h, :data)
    haskey(nd, key) && return getproperty(nd, name)
    error("TwixHdr has no section '$key'. Available: $(sort(collect(keys(nd))))")
end

function Base.setproperty!(h::TwixHdr, name::Symbol, value)
    name === :data && return setfield!(h, :data, value)
    getfield(h, :data)[String(name)] = value
end

function Base.propertynames(h::TwixHdr, private::Bool=false)
    propertynames(getfield(h, :data), private)
end

function Base.show(io::IO, h::TwixHdr)
    nd = getfield(h, :data)
    print(io, "TwixHdr with sections: ", join(sort(collect(keys(nd))), ", "))
end

function Base.show(io::IO, ::MIME"text/plain", h::TwixHdr)
    nd = getfield(h, :data)
    println(io, "TwixHdr")
    for k in sort(collect(keys(getfield(nd, :_subtrees))))
        v = getfield(nd, :_subtrees)[k]
        println(io, "  📁 $k ($(length(v)) entries)")
    end
    for k in sort(collect(keys(getfield(nd, :_leaves))))
        v = getfield(nd, :_leaves)[k]
        println(io, "  $k = $v")
    end
end

# Search forwards to NestedDict
search(h::TwixHdr, terms::AbstractString...; kwargs...) = search(getfield(h, :data), terms...; kwargs...)
leaves(h::TwixHdr) = leaves(getfield(h, :data))
