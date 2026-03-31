# TwixHdr and types are now defined in types.jl
# Search functionality is now provided by NestedDict.search()

# ─── Header value conversion helpers ───────────────────────────────────

"""Safely extract a section from the header, returning nothing if missing."""
function _get_section(prot::TwixHdr, name::String)
    haskey(prot.data, name) ? prot.data[name] : nothing
end

"""Convert a header value to Float64, handling string representations."""
_to_float(val::Number) = Float64(val)
_to_float(val) = parse(Float64, split(string(val))[1])

"""Convert a header value to Int, handling string representations."""
_to_int(val::Number) = Int(val)
_to_int(val) = parse(Int, split(string(val))[1])

"""
    _safe_string(bytes::Vector{UInt8}) -> String

Convert bytes to a String, replacing invalid UTF-8 sequences
(common in Latin-1 encoded Siemens headers).
"""
function _safe_string(bytes::Vector{UInt8})
    try
        return String(copy(bytes))
    catch
        # Replace non-ASCII bytes with '?' for safety
        cleaned = copy(bytes)
        for i in eachindex(cleaned)
            if cleaned[i] > 0x7E
                cleaned[i] = UInt8('?')
            end
        end
        return String(cleaned)
    end
end

# ─── ASCCONV parsing ──────────────────────────────────────────────────

"""
    parse_ascconv(buffer::AbstractString) -> NestedDict

Parse ASCCONV section from Siemens header buffer into a tree structure.
E.g., `sKSpace.lBaseResolution = 256` becomes accessible as
`result.sKSpace.lBaseResolution`.
"""
function parse_ascconv(buffer::AbstractString)
    mrprot = NestedDict()
    re_var = r"(?P<name>\S+)\s*=\s*(?P<value>\S+)"
    re_array = r"(\w+)(?:\[([0-9]+)\])?"

    for m in eachmatch(re_var, buffer)
        name_str = m[1]
        value_str = m[2]

        # Try to parse as number
        value = try
            parse(Float64, value_str)
        catch
            value_str
        end

        # Split dotted name + array indices into path segments
        vvarray = collect(eachmatch(re_array, name_str))
        parts = String[]
        for vm in vvarray
            push!(parts, vm[1])
            if vm[2] !== nothing
                push!(parts, vm[2])
            end
        end

        setpath!(mrprot, parts, value)
    end

    return mrprot
end

"""
    parse_xprot(buffer::AbstractString) -> Dict

Parse XProtocol section from Siemens header buffer.
"""
function parse_xprot(buffer::AbstractString)
    xprot = Dict{String,Any}()

    re_param = r"<Param(?:Bool|Long|String|Double)\.\"(\w+)\">\s*\{\s*(?:<Precision>\s*[0-9]*)?\s*([^}]*)"

    for m in eachmatch(re_param, buffer)
        name = String(m[1])
        value = strip(m[2])

        if length(value) < 5000
            # Remove quotes and nested tags
            value = replace(value, r"(\"+ )|( *<\w*> *[^\n]*)" => "")
            value = strip(value)
            # Collapse whitespace
            value = replace(value, r"\s+" => " ")

            value = try
                parse(Float64, value)
            catch
                value
            end
        end

        xprot[name] = value
    end

    return xprot
end

"""
    parse_buffer(buffer::AbstractString) -> NestedDict

Parse a complete header buffer (both ASCCONV and XProtocol sections)
into a single NestedDict tree.
"""
function parse_buffer(buffer::AbstractString)
    re_ascconv = r"### ASCCONV BEGIN[^\n]*\n(.*?)\s*### ASCCONV END ###"s

    ascconv_match = match(re_ascconv, buffer)
    if ascconv_match !== nothing
        prot = parse_ascconv(ascconv_match.captures[1])
    else
        prot = NestedDict()
    end

    # Split around ASCCONV and parse xprot from the rest
    xprot_parts = split(buffer, r"### ASCCONV BEGIN[^\n]*\n.*?\s*### ASCCONV END ###"s)
    xprot_buffer = join(xprot_parts, "")
    prot2 = parse_xprot(xprot_buffer)

    # Merge XProtocol values into the tree
    for (k, v) in prot2
        prot[k] = v
    end

    return prot
end

"""
    read_twix_hdr(fid::IO, prot::TwixHdr) -> (TwixHdr, rstraj)

Read the twix header from a file. Returns the populated header and
optional regridding trajectory.
"""
function read_twix_hdr(fid::IO, prot::TwixHdr)
    nbuffers = read(fid, UInt32)

    for _ in 1:nbuffers
        # Read buffer name (10 bytes)
        tmpBuff = Vector{UInt8}(undef, 10)
        readbytes!(fid, tmpBuff, 10)
        bufname_raw = String(copy(tmpBuff))
        # Extract alphanumeric prefix
        m = match(r"^\w*", bufname_raw)
        bufname = m !== nothing ? m.match : ""

        # Seek past the name to the length
        skip(fid, length(bufname) - 9)
        buflen_arr = read(fid, UInt32)
        buflen = Int(buflen_arr)

        # Read the buffer contents
        buffer_bytes = Vector{UInt8}(undef, buflen)
        actual_read = readbytes!(fid, buffer_bytes, buflen)

        warningString = nothing
        if length(bufname) == 0
            warningString = "\nEmpty buffer name at file offset $(position(fid)): file may be corrupt or unsupported\n"
        elseif actual_read < buflen
            warningString = "\nRead only $actual_read of expected $buflen bytes (offset $(position(fid))); file may be corrupt or unsupported\n"
        end

        if warningString !== nothing
            warningString *= "Header read stopped prematurely.\n"
            @warn warningString
            break
        end

        # Decode bytes to string (replace invalid UTF-8 for Latin-1 headers)
        buffer = _safe_string(buffer_bytes)
        # Trim whitespace and drop blank lines
        lines = [strip(l) for l in split(buffer, '\n')]
        buffer = join(filter(!isempty, lines), "\n")

        prot.data[bufname] = parse_buffer(buffer)
    end

    rstraj = nothing

    # Read gridding info
    meas = _get_section(prot, "Meas")
    if meas !== nothing && haskey(meas, "alRegridMode")
        regrid_mode = _to_int(meas["alRegridMode"])

        if regrid_mode > 1
            ncol = _to_int(meas["alRegridDestSamples"])

            dwelltime = _to_float(meas["aflRegridADCDuration"]) / ncol
            gr_adc = zeros(Float32, ncol)
            start = _to_float(meas["alRegridDelaySamplesTime"])
            time_adc = start .+ dwelltime .* (collect(0:ncol-1) .+ 0.5)
            rampup_time = _to_float(meas["alRegridRampupTime"])
            flattop_time = _to_float(meas["alRegridFlattopTime"])
            rampdown_time = _to_float(meas["alRegridRampdownTime"])

            ixUp = findall(time_adc .< rampup_time)
            ixFlat = findall((time_adc .>= rampup_time) .& (time_adc .<= rampup_time + flattop_time))
            ixDn = findall((time_adc .> rampup_time + flattop_time))

            gr_adc[ixFlat] .= 1.0f0
            if regrid_mode == 2
                # Trapezoidal gradient
                gr_adc[ixUp] .= Float32.(time_adc[ixUp] ./ rampup_time)
                gr_adc[ixDn] .= Float32.(1.0 .- (time_adc[ixDn] .- rampup_time .- flattop_time) ./ rampdown_time)
            elseif regrid_mode == 4
                gr_adc[ixUp] .= Float32.(sin.(π / 2 .* time_adc[ixUp] ./ rampup_time))
                gr_adc[ixDn] .= Float32.(sin.(π / 2 .* (1.0 .+ (time_adc[ixDn] .- rampup_time .- flattop_time) ./ rampdown_time)))
            else
                error("regridding mode unknown")
            end

            # Ensure gr_adc is always positive
            gr_adc .= max.(gr_adc, 1.0f-4)

            # Cumulative trapezoid integration
            cum_trap = cumtrapz(gr_adc)
            rstraj = (cum_trap .- ncol / 2) ./ sum(gr_adc)
            mid = div(ncol, 2)
            rstraj .-= (rstraj[mid] + rstraj[mid+1]) / 2

            # Scale by kmax
            meas_yaps = _get_section(prot, "MeasYaps")
            if meas_yaps !== nothing
                base_res = _to_float(meas_yaps["sKSpace.lBaseResolution"])
                readout_fov = _to_float(meas_yaps["sSliceArray.asSlice.0.dReadoutFOV"])
                kmax = base_res / readout_fov
                rstraj .*= kmax
            end
        end
    end

    return prot, rstraj
end

"""
    cumtrapz(y)

Cumulative trapezoidal integration (like scipy.integrate.cumulative_trapezoid).
Returns a vector of length(y) with 0 prepended.
"""
function cumtrapz(y::AbstractVector)
    n = length(y)
    result = zeros(eltype(y), n)
    for i in 2:n
        result[i] = result[i-1] + 0.5 * (y[i-1] + y[i])
    end
    return result
end