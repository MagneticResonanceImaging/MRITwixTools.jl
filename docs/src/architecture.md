# Architecture

This page documents the internal design of MapVBVD.jl for contributors and maintainers.

## File Structure

```
src/
├── MapVBVD.jl            # Module definition, exports, mapVBVD() entry point
├── nested_dict.jl        # NestedDict — tree-structured dict with tab-completion
├── mdh_constants.jl      # Named constants for MDH binary layout
├── types.jl              # Struct definitions (ScanData, TwixObj, MDH, TwixHdr, etc.)
├── read_twix_hdr.jl      # Header parsing (ASCCONV + XProtocol)
├── twix_map_obj.jl       # ScanData methods (dimensions, flags, data I/O)
└── mdh.jl                # MDH binary parsing (bit ops, loop_mdh_read, evalMDH)
```

### Include Order

Include order matters — types must be defined before they're used in method signatures:

```
nested_dict.jl → mdh_constants.jl → types.jl → read_twix_hdr.jl → twix_map_obj.jl → mdh.jl
```

The `mapVBVD()` entry point lives in `MapVBVD.jl` after all includes, since it depends on everything.

## Type Hierarchy

```
mapVBVD() → TwixObj
  ├── "hdr" → TwixHdr (NestedDict wrapper)
  │     └── sections as NestedDict trees: hdr.MeasYaps.sKSpace.lBaseResolution → 256
  └── "image" → ScanData
        ├── readinfo::ReadInfo          (binary layout params)
        ├── removeOS, regrid, ...       (Bool processing flags)
        ├── meta::Union{Nothing, AcquisitionMeta}  (per-acquisition MDH data)
        ├── dims::Union{Nothing, DimSizes}         (computed dimension extents)
        └── isBrokenFile::Bool
```

## The `getfield` Rule

!!! danger "Critical for contributors"
    Because `getproperty` is overridden on `NestedDict`, `TwixHdr`, `TwixObj`, and `ScanData`, **all internal code must use `getfield(obj, :field)` instead of `obj.field`** when accessing actual struct fields.

This is the most common source of bugs when modifying this code:

```julia
# WRONG — goes through getproperty, may infinite-loop or error:
n._subtrees
h.data
t._data

# CORRECT:
getfield(n, :_subtrees)
getfield(h, :data)
getfield(t, :_data)
```

The `NestedDict` helpers (`_st`, `_lv`, `_has`, `_get`, `_set!`, `_del!`) encapsulate this for `NestedDict`.

## Key Design Decisions

### 1. NestedDict with Split Storage

**Problem**: Julia's REPL tab-completion uses `Core.Compiler.return_type` to determine what `getproperty` returns. With `Dict{String,Any}`, the return type is `Any`, and tab-completion fails beyond the first level.

**Solution**: Split internal storage into two typed dicts:

```julia
struct NestedDict
    _subtrees::Dict{String,NestedDict}  # child NestedDicts
    _leaves::Dict{String,Any}           # leaf values (numbers, strings, etc.)
end
```

A type-annotated helper ensures the compiler sees `NestedDict` as the return type for subtree access:

```julia
_getprop_subtree(n::NestedDict, key::String)::NestedDict = getfield(n, :_subtrees)[key]
```

The REPL's inference follows this path, sees `::NestedDict`, and enables chained tab-completion at every level.

!!! note "No existing Julia package provides this"
    `PropertyDicts.jl` is the closest but returns `Any` from `getproperty`, breaking REPL inference. If Julia's REPL ever gains evaluation-based completion (instead of inference-based), a simpler approach would suffice.

### 2. TwixObj Return Type Narrowing

Same technique for `TwixObj`:

```julia
_twixobj_val(t::TwixObj, key::String)::Union{TwixHdr, ScanData} = getfield(t, :_data)[key]
```

Julia's REPL handles small `Union` types well — it offers `propertynames` from both types, with the correct ones appearing at runtime.

### 3. ScanData — Flat Flags, Composed Sub-structs

Processing flags (`removeOS`, `regrid`, `doAverage`, etc.) are direct `Bool` fields on `ScanData`. No separate `ProcessingFlags` struct — this keeps things simple.

Defaults are defined in two places only:
- **`ScanData` constructor** — keyword arguments, all `false`
- **`mapVBVD` function** — keyword arguments forwarded to `ScanData`

### 4. Immutable AcquisitionMeta

`AcquisitionMeta` is immutable. Trimming acquisitions (in `tryAndFixLastMdh!`) requires rebuilding the entire struct. This is a deliberate trade-off for type stability during data reading.

### 5. Named Constants for MDH Binary Layout

All magic numbers are extracted to `mdh_constants.jl`:

```julia
const MDH_SIZE_VB = 128
const BIT_ACQEND = 0
const BIT_REFLECT = 24
const DIM_COL = 1
const SCAN_TYPES = ["image", "noise", "phasecor", ...]
```

## Data Flow

```
mapVBVD(filename)
  ├── read_twix_hdr(fid, prot)          # Parse header sections into NestedDict trees
  │     ├── parse_buffer(buffer)         # Splits ASCCONV and XProtocol
  │     │     ├── parse_ascconv(buf)     # Dotted paths → NestedDict via setpath!
  │     │     └── parse_xprot(buf)       # XML-like tags → flat Dict
  │     └── _safe_string(bytes)          # Latin-1 → UTF-8 conversion
  │
  ├── loop_mdh_read(fid, version, ...)   # Binary MDH scan, returns mdh_blob + filePos
  ├── evalMDH(mdh_blob, version)         # Parse blob → MDH + MDHMask structs
  ├── _assign_scans!(obj, mdh, mask, filePos)  # Route acquisitions to scan types
  │     └── readMDH!(scandata, mdh, filePos, selector)  # Populate AcquisitionMeta
  └── compute_dims!(scandata)            # Compute DimSizes from AcquisitionMeta
```

## Performance Notes

Three performance optimizations were applied to hot paths:

1. **Doubling growth for `mdh_blob`** (`mdh.jl:loop_mdh_read`) — the MDH byte buffer uses a doubling strategy with `copyto!` instead of `hcat` with fixed 4096-column growth. Reduces total copy cost from O(n²) to O(n).

2. **Bulk vectorized `reinterpret` in `evalMDH`** (`mdh.jl`) — instead of per-column `reinterpret` loops, extracts contiguous byte sub-matrices and uses `reshape(reinterpret(..., vec(...)), ...)` for a single bulk operation per data type.

3. **Zero-copy `ComplexF32` read buffer** (`twix_map_obj.jl:readData`) — Siemens stores interleaved `(real, imag)` Float32 pairs, which have identical memory layout to `ComplexF32`. A pre-allocated `Vector{ComplexF32}` is read via `read!`, eliminating 3 temporary array allocations per acquisition.

With `removeOS=false` (the default), data reading is close to disk-limited on modern SSDs.

## Type Improvements over Original

| Field | Before | After |
|-------|--------|-------|
| Loop counters | `Float64` | `Int32` |
| Dimension sizes | `Float64` | `Int` |
| File positions | `Float64` | `Int64` |
| Reflection flags | `Vector{Bool}` | `BitVector` |

## ASCCONV Parsing

Siemens ASCCONV sections contain lines like:

```
sKSpace.lBaseResolution = 256
sTXSPEC.asNucleusInfo[0].tNucleus = "1H"
```

`parse_ascconv` splits these into path segments and calls `setpath!`:

```julia
setpath!(result, ["sKSpace", "lBaseResolution"], 256.0)
setpath!(result, ["sTXSPEC", "asNucleusInfo", "0", "tNucleus"], "\"1H\"")
```

Array indices like `[0]` become string keys `"0"` in the tree. These are included in `propertynames` (via the `all(isdigit, k)` check) so tab-completion works for them too.

## Known Limitations / Future Work

1. **XProtocol parsing is minimal** — only extracts `ParamBool`, `ParamLong`, `ParamString`, `ParamDouble`. Nested structures (`ParamArray`, `ParamMap`) are not parsed.

2. **`AcquisitionMeta` is immutable** — trimming requires rebuilding the entire struct.

3. **Latin-1 headers** — `_safe_string` replaces non-ASCII bytes with `?`. A proper Latin-1 → UTF-8 conversion (e.g., via `StringEncodings.jl`) would be more correct.

4. **OS removal performance** — when `removeOS=true`, per-channel FFT/IFFT calls dominate CPU time. Batching into `ifft!(matrix, 1)` and/or using pre-planned FFTW transforms would improve throughput.

5. **Regridding performance** — per-channel interpolation loops could benefit from threading.