# Header Access

Siemens twix files contain rich protocol headers with hundreds of parameters organized in a tree structure. MRITwixTools.jl parses these into a [`NestedDict`](@ref) tree that supports **tab-completion at every level** in the Julia REPL.

## Accessing Header Values

```julia
twixObj = read_twix("meas.dat")
hdr = twixObj.hdr
```

### Dot Access (Tab-Completable)

The primary way to explore headers interactively:

```julia
hdr.MeasYaps.sKSpace.lBaseResolution       # => 256.0
hdr.MeasYaps.sTXSPEC.asNucleusInfo         # => NestedDict(...)

# Array indices from ASCCONV (e.g., asNucleusInfo[0]) become string keys:
hdr.MeasYaps.sTXSPEC.asNucleusInfo."0".tNucleus  # => "\"1H\""
# Or equivalently:
hdr.MeasYaps.sTXSPEC.asNucleusInfo["0"]["tNucleus"]
```

Tab-completion works at every level — type `hdr.Meas<TAB>` to see available sections, then `hdr.MeasYaps.sK<TAB>` to drill deeper.

### Path String Access

For programmatic access using dotted path strings:

```julia
hdr["MeasYaps.sKSpace.lBaseResolution"]     # => 256.0
hdr["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus"]  # => "\"1H\""
```

### Header Sections

A typical header contains these top-level sections:

| Section | Contents |
|---------|----------|
| `Meas` | XProtocol measurement parameters (regridding, etc.) |
| `MeasYaps` | ASCCONV parameters — the most commonly used section |
| `Phoenix` | Phoenix protocol (often mirrors MeasYaps) |
| `Spice` | Spice protocol (if present) |
| `Dicom` | DICOM-related protocol parameters |

## Searching Headers

### Search by Key Path

Find all parameters whose dotted path matches one or more terms:

```julia
# Single term — finds all paths containing "lBaseRes"
search(hdr, "lBaseRes")
# => ["MeasYaps.sKSpace.lBaseResolution" => 256.0,
#     "Phoenix.sKSpace.lBaseResolution" => 128.0]

# Multiple terms — AND logic, all must match
search(hdr, "sTXSPEC", "Nucleus")
# => ["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus" => "\"1H\""]
```

### Search by Value

Pass `search_values=true` to also match against the string representation of leaf values:

```julia
# Find any parameter whose value contains "1H"
search(hdr, "1H", search_values=true)
# => ["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus" => "\"1H\""]

# Combined: path must contain "Nucleus" AND value must contain "1H"
search(hdr, "Nucleus", "1H", search_values=true)
```

This is useful when you know a parameter's *value* but not where it lives in the tree.

### Search Options

```julia
search(hdr, terms...;
    regex = true,           # treat terms as case-insensitive regexes
    leaves_only = true,     # only return leaf values (not subtree nodes)
    search_values = false,  # also match against leaf values
)
```

### Listing All Values

```julia
# Get every leaf in the entire header tree
all_params = leaves(hdr)
# => ["MeasYaps.sKSpace.lBaseResolution" => 256.0,
#     "MeasYaps.sKSpace.ucDimension" => 4.0,
#     ...]
```

!!! tip "For details on how tab-completion works internally"
    See [Tab-Completion Internals](../devguide/tab_completion.md) in the Developer Guide.