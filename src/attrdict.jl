"""
    AttrDict

A dictionary that allows attribute-style access to its values.
Julia equivalent of the Python AttrDict class. Uses a regular Dict internally
but allows `obj.key` access via `getproperty`/`setproperty!`.
"""
mutable struct AttrDict
    _data::Dict{Any,Any}
end

AttrDict() = AttrDict(Dict{Any,Any}())

function AttrDict(pairs::Pair...)
    d = Dict{Any,Any}()
    for (k, v) in pairs
        d[k] = v
    end
    AttrDict(d)
end

# Dict-like interface
Base.getindex(a::AttrDict, key) = a._data[key]
Base.setindex!(a::AttrDict, value, key) = (a._data[key] = value)
Base.haskey(a::AttrDict, key) = haskey(a._data, key)
Base.keys(a::AttrDict) = keys(a._data)
Base.values(a::AttrDict) = values(a._data)
Base.length(a::AttrDict) = length(a._data)
Base.iterate(a::AttrDict) = iterate(a._data)
Base.iterate(a::AttrDict, state) = iterate(a._data, state)
Base.delete!(a::AttrDict, key) = delete!(a._data, key)
Base.pop!(a::AttrDict, key) = pop!(a._data, key)
Base.pop!(a::AttrDict, key, default) = pop!(a._data, key, default)
Base.merge!(a::AttrDict, d::Dict) = merge!(a._data, d)
Base.merge!(a::AttrDict, d::AttrDict) = merge!(a._data, d._data)

function Base.getproperty(a::AttrDict, name::Symbol)
    if name === :_data
        return getfield(a, :_data)
    end
    key = String(name)
    if haskey(a._data, key)
        return a._data[key]
    else
        error("AttrDict has no key '$key'")
    end
end

function Base.setproperty!(a::AttrDict, name::Symbol, value)
    if name === :_data
        return setfield!(a, :_data, value)
    end
    a._data[String(name)] = value
end

function Base.propertynames(a::AttrDict, private::Bool=false)
    ks = Symbol[]
    for k in keys(a._data)
        if k isa AbstractString
            push!(ks, Symbol(k))
        end
    end
    ks
end

function Base.show(io::IO, a::AttrDict)
    print(io, "AttrDict(")
    print(io, join(["$k => ..." for k in keys(a._data)], ", "))
    print(io, ")")
end

"""
Update AttrDict with key-value pairs from another AttrDict or Dict.
"""
function update!(a::AttrDict, other::AttrDict)
    for (k, v) in other._data
        a._data[k] = v
    end
    a
end

function update!(a::AttrDict, other::Dict)
    for (k, v) in other
        a._data[k] = v
    end
    a
end

function update!(a::AttrDict, pairs::Pair...)
    for (k, v) in pairs
        a._data[k] = v
    end
    a
end