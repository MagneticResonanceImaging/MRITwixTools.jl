"""
    TwixHdr

Header object for Siemens twix files. Wraps an AttrDict and provides
header search functionality.
"""
mutable struct TwixHdr
    data::AttrDict
end

TwixHdr() = TwixHdr(AttrDict())

Base.getindex(h::TwixHdr, key) = h.data[key]
Base.setindex!(h::TwixHdr, value, key) = (h.data[key] = value)
Base.haskey(h::TwixHdr, key) = haskey(h.data, key)
Base.keys(h::TwixHdr) = keys(h.data)
Base.values(h::TwixHdr) = values(h.data)
Base.iterate(h::TwixHdr) = iterate(h.data)
Base.iterate(h::TwixHdr, state) = iterate(h.data, state)

function Base.getproperty(h::TwixHdr, name::Symbol)
    if name === :data
        return getfield(h, :data)
    end
    key = String(name)
    if haskey(h.data, key)
        return h.data[key]
    else
        error("TwixHdr has no key '$key'")
    end
end

function Base.setproperty!(h::TwixHdr, name::Symbol, value)
    if name === :data
        return setfield!(h, :data, value)
    end
    h.data[String(name)] = value
end

function Base.show(io::IO, h::TwixHdr)
    println(io, "***twix_hdr***")
    print(io, "Top level data structures: ")
    println(io, join(collect(keys(h.data)), "\n"))
end

function update!(h::TwixHdr, pairs::Pair...)
    for (k, v) in pairs
        h.data[k] = v
    end
    h
end

function update!(h::TwixHdr, d::Dict)
    for (k, v) in d
        h.data[k] = v
    end
    h
end

"""
    search_using_tuple(s_terms, key; regex=true)

Check whether all search terms match a key (tuple of strings).
"""
function search_using_tuple(s_terms, key; regex::Bool=true)
    if regex
        function regex_tuple(pattern, key_tuple)
            re_comp = Regex(pattern, "i")
            for k in key_tuple
                if occursin(re_comp, string(k))
                    return true
                end
            end
            return false
        end
        return all(st -> regex_tuple(st, key isa Tuple ? key : (key,)), s_terms)
    else
        return all(st -> st in key, s_terms)
    end
end

"""
    search_for_keys(hdr, search_terms; top_lvl=nothing, print_flag=true, regex=true)

Search header keys for terms.
"""
function search_for_keys(hdr::TwixHdr, search_terms;
                         top_lvl=nothing, print_flag::Bool=true, regex::Bool=true)
    if top_lvl === nothing
        top_lvl_keys = collect(keys(hdr.data))
    elseif top_lvl isa AbstractString
        top_lvl_keys = [top_lvl]
    else
        top_lvl_keys = collect(top_lvl)
    end

    out = Dict{String,Vector}()
    for key in top_lvl_keys
        matching_keys = []
        sub_dict = hdr.data[key]
        if sub_dict isa AttrDict
            list_of_keys = collect(keys(sub_dict))
        else
            list_of_keys = collect(keys(sub_dict))
        end

        for sub_key in list_of_keys
            if search_using_tuple(search_terms, sub_key, regex=regex)
                push!(matching_keys, sub_key)
            end
        end

        if print_flag
            println("$key:")
            for mk in matching_keys
                println("\t$mk: $(sub_dict[mk])")
            end
        end

        out[key] = matching_keys
    end

    return out
end

"""
    parse_ascconv(buffer::AbstractString) -> AttrDict

Parse ASCCONV section from Siemens header buffer.
"""
function parse_ascconv(buffer::AbstractString)
    mrprot = AttrDict()
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

        # Split array name and index
        vvarray = collect(eachmatch(re_array, name_str))
        parts = String[]
        for vm in vvarray
            push!(parts, vm[1])
            if vm[2] !== nothing
                push!(parts, vm[2])
            end
        end

        mrprot[Tuple(parts)] = value
    end

    return mrprot
end

"""
    parse_xprot(buffer::AbstractString) -> Dict

Parse XProtocol section from Siemens header buffer.
"""
function parse_xprot(buffer::AbstractString)
    xprot = Dict{Any,Any}()

    re_param = r"<Param(?:Bool|Long|String|Double)\.\"(\w+)\">\s*\{\s*(?:<Precision>\s*[0-9]*)?\s*([^}]*)"

    for m in eachmatch(re_param, buffer)
        name = m[1]
        value = strip(m[2])

        if length(value) < 5000
            # Remove quotes and nested tags
            value = replace(value, r"(\"+)|( *<\w*> *[^\n]*)" => "")
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
    parse_buffer(buffer::AbstractString) -> AttrDict

Parse a complete header buffer (both ASCCONV and XProtocol sections).
"""
function parse_buffer(buffer::AbstractString)
    re_ascconv = r"### ASCCONV BEGIN[^\n]*\n(.*?)\s*### ASCCONV END ###"s

    ascconv_match = match(re_ascconv, buffer)
    if ascconv_match !== nothing
        prot = parse_ascconv(ascconv_match.match)
    else
        prot = AttrDict()
    end

    # Split around ASCCONV and parse xprot from the rest
    xprot_parts = split(buffer, r"### ASCCONV BEGIN[^\n]*\n.*?\s*### ASCCONV END ###"s)
    xprot_buffer = join(xprot_parts, "")
    prot2 = parse_xprot(xprot_buffer)

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

        # Decode as Latin-1
        buffer = String(buffer_bytes)
        # Trim whitespace and drop blank lines
        lines = [strip(l) for l in split(buffer, '\n')]
        buffer = join(filter(!isempty, lines), "\n")

        prot.data[bufname] = parse_buffer(buffer)
    end

    rstraj = nothing

    # Read gridding info
    if haskey(prot.data, "Meas") && haskey(prot.data["Meas"], "alRegridMode")
        regrid_mode_str = prot.data["Meas"]["alRegridMode"]
        regrid_mode = if regrid_mode_str isa Number
            Int(regrid_mode_str)
        else
            parse(Int, split(string(regrid_mode_str))[1])
        end

        if regrid_mode > 1
            ncol = if prot.data["Meas"]["alRegridDestSamples"] isa Number
                Int(prot.data["Meas"]["alRegridDestSamples"])
            else
                parse(Int, split(string(prot.data["Meas"]["alRegridDestSamples"]))[1])
            end

            _get_float(val) = val isa Number ? Float64(val) : parse(Float64, split(string(val))[1])

            dwelltime = _get_float(prot.data["Meas"]["aflRegridADCDuration"]) / ncol
            gr_adc = zeros(Float32, ncol)
            start = _get_float(prot.data["Meas"]["alRegridDelaySamplesTime"])
            time_adc = start .+ dwelltime .* (collect(0:ncol-1) .+ 0.5)
            rampup_time = _get_float(prot.data["Meas"]["alRegridRampupTime"])
            flattop_time = _get_float(prot.data["Meas"]["alRegridFlattopTime"])
            rampdown_time = _get_float(prot.data["Meas"]["alRegridRampdownTime"])

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
            if haskey(prot.data, "MeasYaps")
                meas_yaps = prot.data["MeasYaps"]
                base_res = meas_yaps[("sKSpace", "lBaseResolution")]
                readout_fov = meas_yaps[("sSliceArray", "asSlice", "0", "dReadoutFOV")]
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