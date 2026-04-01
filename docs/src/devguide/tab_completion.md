# Tab-Completion Internals

This page explains how MapVBVD.jl achieves deep REPL tab-completion through the entire header tree. This is a developer-facing design document — for user-facing header usage, see [Header Access](../guide/headers.md).

## The Problem

Julia's REPL tab-completion uses compile-time type inference (`Core.Compiler.return_type`) to determine what `getproperty` returns, then calls `propertynames` on that inferred type. With a plain `Dict{String, Any}`, the inferred return type is `Any`, and completion stops after the first level.

This means a naive implementation like:

```julia
struct SimpleHeader
    data::Dict{String, Any}  # values can be sub-dicts or leaves
end
Base.getproperty(h::SimpleHeader, name::Symbol) = getfield(h, :data)[String(name)]
```

...would only offer tab-completion at the first level. `hdr.MeasYaps.<TAB>` would produce nothing.

## The Solution: Split Storage in NestedDict

MapVBVD.jl splits internal storage into two typed dictionaries:

```julia
struct NestedDict
    _subtrees::Dict{String, NestedDict}   # child NestedDicts
    _leaves::Dict{String, Any}            # leaf values (numbers, strings, etc.)
end
```

A type-annotated helper ensures the compiler sees `NestedDict` as the return type when accessing subtrees:

```julia
_getprop_subtree(n::NestedDict, key::String)::NestedDict = getfield(n, :_subtrees)[key]

function Base.getproperty(n::NestedDict, name::Symbol)
    key = String(name)
    subtrees = getfield(n, :_subtrees)
    if haskey(subtrees, key)
        return _getprop_subtree(n, key)  # compiler infers ::NestedDict
    end
    leaves = getfield(n, :_leaves)
    if haskey(leaves, key)
        return leaves[key]
    end
    error("NestedDict has no key: $key")
end
```

The key insight is the `::NestedDict` return type annotation on `_getprop_subtree`. The compiler follows this path, infers `NestedDict` as the return type, and calls `propertynames(::NestedDict)` — which returns all keys from both `_subtrees` and `_leaves`. This enables **unlimited chained tab-completion** through the entire header tree.

## TwixObj Return Type Narrowing

The same technique applies to `TwixObj`:

```julia
_twixobj_val(t::TwixObj, key::String)::Union{TwixHdr, RawData} = getfield(t, :_data)[key]
```

Julia's REPL handles small `Union` types well — it offers `propertynames` from *both* `TwixHdr` and `RawData`, with the correct ones appearing at runtime based on evaluation.

## TwixHdr Delegation

`TwixHdr` wraps a `NestedDict` and delegates `getproperty` to it:

```julia
function Base.getproperty(h::TwixHdr, name::Symbol)
    name === :data && return getfield(h, :data)
    nd = getfield(h, :data)
    haskey(nd, key) && return getproperty(nd, name)  # delegates to NestedDict
    ...
end
```

This preserves the `::NestedDict` return type inference through the `TwixHdr` layer, so tab-completion flows through `twixObj.hdr.MeasYaps.sKSpace.<TAB>` seamlessly.

## The `getfield` Consequence

Because `getproperty` is overridden on all major types, **internal code must always use `getfield(obj, :field)`** instead of `obj.field` when accessing actual struct fields. The helper functions (`_st`, `_lv`, `_has`, `_get`, `_set!`, `_del!`) encapsulate this for `NestedDict`.

See the [Architecture](architecture.md) page for more details on this rule.

## Why Not PropertyDicts.jl?

`PropertyDicts.jl` is the closest existing Julia package, but it returns `Any` from `getproperty`, which breaks REPL inference. If Julia's REPL ever gains evaluation-based completion (instead of inference-based), `PropertyDicts.jl` + a search function would suffice and MapVBVD.jl's split-storage approach could be simplified.

## Numeric String Keys

ASCCONV array indices like `asNucleusInfo[0]` become string keys `"0"` in the NestedDict tree. These are included in `propertynames` output (via an `all(isdigit, k)` check) so tab-completion lists them alongside named keys.