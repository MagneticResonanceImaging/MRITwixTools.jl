# Architecture

This page documents the internal design of MapVBVD.jl for contributors and maintainers.

## File Structure

```
src/
├── MapVBVD.jl            # Module definition, exports, mapVBVD() entry point
├── nested_dict.jl        # NestedDict — tree-structured dict with tab-completion
├── mdh_constants.jl      # Named constants for MDH binary layout
├── types.jl              # Struct definitions (RawData, TwixObj, MDH, TwixHdr, etc.)
├── read_twix_hdr.jl      # Header parsing (ASCCONV + XProtocol)
├── twix_map_obj.jl       # RawData methods (dimensions, flags, data I/O)
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
  └── "image" → RawData
        ├── readinfo::ReadInfo          (binary layout params)
        ├── removeOS, regrid, ...       (Bool processing flags)
        ├── meta::Union{Nothing, AcquisitionMeta}  (per-acquisition MDH data)
        ├── dims::Union{Nothing, DimSizes}         (computed dimension extents)
        └── isBrokenFile::Bool
```

## The `getfield` Rule

!!! danger "Critical for contributors"
    Because `getproperty` is overridden on `NestedDict`, `TwixHdr`, `TwixObj`, and `RawData`, **all internal code must use `getfield(obj, :field)` instead of `obj.field`** when accessing actual struct fields.

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

### 1. RawData — Flat Flags, Composed Sub-structs

Processing flags (`removeOS`, `regrid`, `doAverage`, etc.) are direct `Bool` fields on `RawData`. No separate `ProcessingFlags` struct — this keeps things simple.

Defaults are defined in two places only:
- **`RawData` constructor** — keyword arguments, all `false`
- **`mapVBVD` function** — keyword arguments forwarded to `RawData`

### 2. Immutable AcquisitionMeta

`AcquisitionMeta` is immutable. Trimming acquisitions (in `tryAndFixLastMdh!`) requires rebuilding the entire struct. This is a deliberate trade-off for type stability during data reading.

### 3. Named Constants for MDH Binary Layout

All magic numbers are extracted to `mdh_constants.jl`:

```julia
const MDH_SIZE_VB = 128
const BIT_ACQEND = 0
const BIT_REFLECT = 24
const DIM_COL = 1
const SCAN_TYPES = ["image", "noise", "phasecor", ...]
```

### 4. Twix Format Versions

The `version` field on `RawData` is a `Symbol` — either `:vb` or `:vd`:

- **`:vb`** — VB-format files: single-measurement, 128-byte MDH, channel header embedded in MDH
- **`:vd`** — VD/VE/XA-format files: multi-raid, 184-byte MDH, separate scan and channel headers

The `:vd` label covers all post-VB formats (VD, VE, XA) since they share the same binary layout. Symbols are used instead of strings for zero-allocation comparison (`===`) and to enable potential method dispatch.

### 5. Type Improvements over Original

| Field | Before | After |
|-------|--------|-------|
| Loop counters | `Float64` | `Int32` |
| Dimension sizes | `Float64` | `Int` |
| File positions | `Float64` | `Int64` |
| Reflection flags | `Vector{Bool}` | `BitVector` |

For details on the NestedDict split-storage design and how REPL tab-completion works, see [Tab-Completion Internals](tab_completion.md).

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

## Performance Notes

Three performance optimizations were applied to hot paths:

1. **Doubling growth for `mdh_blob`** (`mdh.jl:loop_mdh_read`) — the MDH byte buffer uses a doubling strategy with `copyto!` instead of `hcat` with fixed 4096-column growth. Reduces total copy cost from O(n²) to O(n).

2. **Bulk vectorized `reinterpret` in `evalMDH`** (`mdh.jl`) — instead of per-column `reinterpret` loops, extracts contiguous byte sub-matrices and uses `reshape(reinterpret(..., vec(...)), ...)` for a single bulk operation per data type.

3. **Zero-copy `ComplexF32` read buffer** (`twix_map_obj.jl:readData`) — Siemens stores interleaved `(real, imag)` Float32 pairs, which have identical memory layout to `ComplexF32`. A pre-allocated `Vector{ComplexF32}` is read via `read!`, eliminating 3 temporary array allocations per acquisition.

With `removeOS=false` (the default), data reading is close to disk-limited on modern SSDs.

## Known Limitations / Future Work

1. **XProtocol parsing is minimal** — only extracts `ParamBool`, `ParamLong`, `ParamString`, `ParamDouble`. Nested structures (`ParamArray`, `ParamMap`) are not parsed.

2. **`AcquisitionMeta` is immutable** — trimming requires rebuilding the entire struct.

3. **Latin-1 headers** — `_safe_string` replaces non-ASCII bytes with `?`. A proper Latin-1 → UTF-8 conversion (e.g., via `StringEncodings.jl`) would be more correct.

4. **OS removal performance** — when `removeOS=true`, per-channel FFT/IFFT calls dominate CPU time. Batching into `ifft!(matrix, 1)` and/or using pre-planned FFTW transforms would improve throughput.

5. **Regridding performance** — per-channel interpolation loops could benefit from threading.