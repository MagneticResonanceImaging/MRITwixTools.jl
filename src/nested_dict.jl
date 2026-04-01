"""
    NestedDict

A recursively nested dictionary with property-style access for navigating
Siemens MRI header data. Supports:

- **Dot access**: `hdr.MeasYaps.sKSpace.lBaseResolution`
- **Path strings**: `hdr["MeasYaps.sKSpace.lBaseResolution"]`
- **Tab completion**: at every level via `propertynames`
- **Search**: `search(hdr, "sTXSPEC", "Nucleus")` finds all matching paths
- **Iteration**: standard `keys`, `values`, `pairs`, `length`

# Implementation note
Subtrees (NestedDict children) are stored separately from leaf values
in a typed dict, enabling Julia's REPL to infer the return type of
`getproperty` for chained tab-completion.
"""
struct NestedDict
    _subtrees::Dict{String,NestedDict}
    _leaves::Dict{String,Any}
end

NestedDict() = NestedDict(Dict{String,NestedDict}(), Dict{String,Any}())

function NestedDict(pairs::Pair{String}...)
    st = Dict{String,NestedDict}()
    lv = Dict{String,Any}()
    for (k, v) in pairs
        if v isa NestedDict
            st[k] = v
        else
            lv[k] = v
        end
    end
    NestedDict(st, lv)
end

# ─── Internal helpers ───────────────────────────────────────────────────

_st(n::NestedDict) = getfield(n, :_subtrees)
_lv(n::NestedDict) = getfield(n, :_leaves)

_has(n::NestedDict, k::String) = haskey(_st(n), k) || haskey(_lv(n), k)

function _get(n::NestedDict, k::String)
    haskey(_st(n), k) && return _st(n)[k]
    return _lv(n)[k]
end

function _set!(n::NestedDict, k::String, v::NestedDict)
    delete!(_lv(n), k)
    _st(n)[k] = v
end

function _set!(n::NestedDict, k::String, v)
    delete!(_st(n), k)
    _lv(n)[k] = v
end

function _del!(n::NestedDict, k::String)
    delete!(_st(n), k)
    delete!(_lv(n), k)
end

_allkeys(n::NestedDict) = Iterators.flatten((keys(_st(n)), keys(_lv(n))))

# ─── Dict interface ─────────────────────────────────────────────────────

Base.haskey(n::NestedDict, key::AbstractString) = _has(n, String(key))
Base.keys(n::NestedDict) = collect(_allkeys(n))
Base.values(n::NestedDict) = [_get(n, k) for k in _allkeys(n)]
Base.length(n::NestedDict) = length(n._subtrees) + length(n._leaves)
Base.isempty(n::NestedDict) = isempty(n._subtrees) && isempty(n._leaves)
Base.delete!(n::NestedDict, key::AbstractString) = _del!(n, String(key))

function Base.iterate(n::NestedDict)
    allk = collect(_allkeys(n))
    isempty(allk) && return nothing
    k = allk[1]
    return (k => _get(n, k)), (allk, 2)
end

function Base.iterate(n::NestedDict, state)
    allk, idx = state
    idx > length(allk) && return nothing
    k = allk[idx]
    return (k => _get(n, k)), (allk, idx + 1)
end

Base.pairs(n::NestedDict) = [k => _get(n, k) for k in _allkeys(n)]

function Base.setindex!(n::NestedDict, val, key::AbstractString)
    _set!(n, String(key), val)
end

# getindex: supports dot-path strings like "MeasYaps.sKSpace.lBaseResolution"
function Base.getindex(n::NestedDict, path::String)
    _has(n, path) && return _get(n, path)

    parts = split(path, '.')
    length(parts) == 1 && throw(KeyError(path))

    node = n
    for (i, p) in enumerate(parts)
        key = String(p)
        if !_has(node, key)
            tried = join(parts[1:i], ".")
            avail = sort(collect(keys(node)))
            error("Key '$tried' not found. Available: $(avail)")
        end
        val = _get(node, key)
        if i == length(parts)
            return val
        elseif val isa NestedDict
            node = val
        else
            error("'$(join(parts[1:i], "."))' is a leaf value ($val), not a subtree")
        end
    end
end

# ─── Property access (with type-stable subtree access) ──────────────────



# Property access: subtrees return NestedDict, leaves return their value.
# The ::NestedDict annotation on the subtree-only method helps Julia's REPL
# infer the return type for chained tab-completion.
function _getprop_subtree(n::NestedDict, key::String)::NestedDict
    return getfield(n, :_subtrees)[key]
end

function Base.getproperty(n::NestedDict, name::Symbol)
    name === :_subtrees && return getfield(n, :_subtrees)
    name === :_leaves && return getfield(n, :_leaves)
    key = String(name)











    st = getfield(n, :_subtrees)
    if haskey(st, key)
        return _getprop_subtree(n, key)
    end
    lv = getfield(n, :_leaves)
    if haskey(lv, key)
        return lv[key]
    end
    avail = sort(collect(keys(n)))
    error("NestedDict has no key '$key'. Available: $(avail)")
end

function Base.setproperty!(n::NestedDict, name::Symbol, val)
    name === :_subtrees && return setfield!(n, :_subtrees, val)
    name === :_leaves && return setfield!(n, :_leaves, val)
    _set!(n, String(name), val)
end

function Base.propertynames(n::NestedDict, private::Bool=false)
    syms = Symbol[]
    for k in _allkeys(n)
        if k isa String && !isempty(k)
            if Base.isidentifier(k) || all(isdigit, k)
                push!(syms, Symbol(k))
            end
        end
    end
    sort!(syms)
    return syms
end

# ─── Path-based insertion ───────────────────────────────────────────────

"""
    setpath!(n::NestedDict, path::Vector{String}, value)

Insert a value at a dotted path, creating intermediate `NestedDict` nodes
as needed. E.g., `setpath!(n, ["sKSpace", "lBaseResolution"], 256)`.
"""
function setpath!(n::NestedDict, path::Vector{String}, value)
    node = n
    for (i, key) in enumerate(path)
        if i == length(path)
            _set!(node, key, value)
        else
            if !haskey(getfield(node, :_subtrees), key)
                getfield(node, :_subtrees)[key] = NestedDict()
            end
            node = getfield(node, :_subtrees)[key]
        end
    end
    return n
end

# ─── Search ─────────────────────────────────────────────────────────────

"""
    search(n::NestedDict, terms...; regex=true, leaves_only=true, search_values=false) -> Vector{Pair{String,Any}}

Search all paths in the tree for entries whose full dotted path matches
**all** given terms. Returns a vector of `"dotted.path" => value` pairs.

# Keyword Arguments
- `regex::Bool=true`: treat each term as a case-insensitive regex (otherwise plain substring match)
- `leaves_only::Bool=true`: only return leaf values, not intermediate subtree nodes
- `search_values::Bool=false`: also match terms against the string representation of leaf values

# Examples
```julia
search(hdr, "sTXSPEC", "Nucleus")         # match path components
search(hdr, "lBaseRes")                    # find all keys containing "lBaseRes"
search(hdr, "1H", search_values=true)      # find leaves whose value contains "1H"
search(hdr, "Nucleus", "1H", search_values=true)  # path contains "Nucleus" AND value contains "1H"
```
"""
function search(n::NestedDict, terms::AbstractString...; regex::Bool=true, leaves_only::Bool=true, search_values::Bool=false)
    results = Pair{String,Any}[]
    _search_recurse!(results, n, String[], terms, regex, leaves_only, search_values)
    return results
end

function _search_recurse!(results, node::NestedDict, path::Vector{String},
                           terms, regex::Bool, leaves_only::Bool, search_values::Bool)
    # Search subtrees
    for (key, val) in getfield(node, :_subtrees)
        current_path = vcat(path, [key])
        full_path = join(current_path, ".")
        if !leaves_only && _matches_all(full_path, terms, regex)
            push!(results, full_path => val)
        end

        _search_recurse!(results, val, current_path, terms, regex, leaves_only, search_values)
    end
    # Search leaves
    for (key, val) in getfield(node, :_leaves)
        current_path = vcat(path, [key])
        full_path = join(current_path, ".")

        match_target = if search_values
            full_path * " " * string(val)
        else
            full_path
        end
        if _matches_all(match_target, terms, regex)
            push!(results, full_path => val)
        end
    end
end

function _matches_all(path::String, terms, regex::Bool)
    for term in terms
        if regex
            !occursin(Regex(term, "i"), path) && return false
        else
            !occursin(lowercase(term), lowercase(path)) && return false
        end
    end
    return true
end

# ─── Leaf enumeration ───────────────────────────────────────────────────

"""
    leaves(n::NestedDict) -> Vector{Pair{String,Any}}

Return all leaf (non-NestedDict) values with their full dotted paths.
"""
function leaves(n::NestedDict)
    results = Pair{String,Any}[]
    _leaves_recurse!(results, n, String[])
    return results
end

function _leaves_recurse!(results, node::NestedDict, path::Vector{String})
    for (key, val) in getfield(node, :_subtrees)
        _leaves_recurse!(results, val, vcat(path, [key]))
    end
    for (key, val) in getfield(node, :_leaves)
        push!(results, join(vcat(path, [key]), ".") => val)
    end
end

# ─── Pretty printing ───────────────────────────────────────────────────

function Base.show(io::IO, n::NestedDict)
    nsubs = length(getfield(n, :_subtrees))
    nleaves = length(getfield(n, :_leaves))
    print(io, "NestedDict($(nsubs) sections, $(nleaves) values)")
end

function Base.show(io::IO, ::MIME"text/plain", n::NestedDict)
    nsubs = length(getfield(n, :_subtrees))
    nleaves = length(getfield(n, :_leaves))
    total = nsubs + nleaves
    println(io, "NestedDict with $total entries:")
    for k in sort(collect(keys(getfield(n, :_subtrees))))
        v = getfield(n, :_subtrees)[k]
        nk = length(v)
        println(io, "  📁 $k ($nk entries)")
    end
    for k in sort(collect(keys(getfield(n, :_leaves))))
        v = getfield(n, :_leaves)[k]
        vstr = string(v)
        if length(vstr) > 60
            vstr = vstr[1:57] * "..."
        end
        println(io, "  $k = $vstr")
    end
end

# ─── Merge / update ─────────────────────────────────────────────────────

"""
    merge!(dest::NestedDict, src::NestedDict)

Merge `src` into `dest`, overwriting leaf values and merging subtrees.
"""
function Base.merge!(dest::NestedDict, src::NestedDict)
    for (k, v) in getfield(src, :_subtrees)
        if haskey(getfield(dest, :_subtrees), k)
            merge!(getfield(dest, :_subtrees)[k], v)
        else
            getfield(dest, :_subtrees)[k] = v
        end
    end
    for (k, v) in getfield(src, :_leaves)
        _set!(dest, k, v)
    end
    return dest
end

"""
    merge!(dest::NestedDict, src::Dict)

Merge a plain Dict into a NestedDict (flat, no tree merging).
"""
function Base.merge!(dest::NestedDict, src::Dict)
    for (k, v) in src
        _set!(dest, string(k), v)
    end
    return dest
end
