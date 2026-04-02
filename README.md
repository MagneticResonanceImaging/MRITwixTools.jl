# MRITwixTools.jl

| **Documentation** | **Build Status** |
|:------------------|:-----------------|
| [![][docs-img]][docs-url] | [![][ci-img]][ci-url] |
| | [![][docs-ci-img]][docs-ci-url] |

Native Julia port of the [twixtools](https://github.com/pehses/twixtools) / [pymapVBVD](https://github.com/wtclarke/pymapvbvd) / Matlab [mapVBVD](https://github.com/pehses/mapVBVD) tools for reading Siemens raw MRI data (twix `.dat` files).

Supports both VB and VD/VE/XA software versions.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JakobAsslaender/MRITwixTools.jl")
```

Or in development mode:
```julia
Pkg.develop(path="/path/to/MRITwixTools.jl")
```

## Quick Start

```julia
using MRITwixTools

# Read a twix file (returns raw data by default — no processing)
twixObj = read_twix("meas_MID00305.dat")

# For multi-raid files (VD/VE/XA), twixObj is a Vector{TwixObj}
# For single-raid files (VB), it is a single TwixObj

# Read image data
data = getdata(twixObj.image)

# Or with slicing (1-based Julia indexing)
data = twixObj.image[1:128, :, :]

# Check available scan types
MDH_flags(twixObj)  # e.g. ["image", "noise", "refscan"]
```

## Processing Options

By default, `read_twix` returns raw data with no processing. Enable processing either at load time or afterwards:

```julia
# At load time
twixObj = read_twix("meas.dat", removeOS=true, squeeze=true)

# Or afterwards
twixObj.image.removeOS = true
twixObj.image.squeeze = true
data = getdata(twixObj.image)
```

Available flags (all `false` by default):

```julia
twixObj.image.removeOS = true          # Remove 2× readout oversampling
twixObj.image.regrid = true            # Ramp sample regridding
twixObj.image.doAverage = true         # Average across averages
twixObj.image.averageReps = true       # Average across repetitions
twixObj.image.averageSets = true       # Average across sets
twixObj.image.ignoreSeg = true         # Collapse segments dimension
twixObj.image.squeeze = true           # Drop singleton dimensions
twixObj.image.disableReflect = true    # Skip readout reflection correction
twixObj.image.ignoreROoffcenter = true # Ignore readout off-center shifts
```

## Header Access

Headers support tab-completion at every level:

```julia
hdr = twixObj.hdr

# Dot access (tab-completable)
hdr.MeasYaps.sKSpace.lBaseResolution  # => 256.0

# Path string access
hdr["MeasYaps"]["sKSpace.lBaseResolution"]  # => 256.0

# Search across all header sections (matches key paths)
search(hdr, "lBaseRes")
# => ["MeasYaps.sKSpace.lBaseResolution" => 256.0,
#     "Phoenix.sKSpace.lBaseResolution" => 128.0]

# Search with multiple terms (AND logic)
search(hdr, "sTXSPEC", "Nucleus")
# => ["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus" => "\"1H\""]

# Search by value (also matches against leaf values)
search(hdr, "1H", search_values=true)
# => ["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus" => "\"1H\""]

# Combined: path contains "Nucleus" AND value contains "1H"
search(hdr, "Nucleus", "1H", search_values=true)

# List all leaf values
leaves(hdr)
```

## Comparison with Other Twix Readers

Several tools exist for reading Siemens twix (`.dat`) files:

- [mapVBVD](https://github.com/pehses/mapVBVD) — the original MATLAB tool by Philipp Ehses
- [pymapVBVD](https://github.com/wtclarke/pymapvbvd) — Python port by Will Clarke
- [twixtools](https://github.com/pehses/twixtools) — Python reader/writer with low-level mdb access by Philipp Ehses

### Defaults

| | mapVBVD (MATLAB) | pymapVBVD (Python) | twixtools (Python) | MRITwixTools.jl |
|:---|:---:|:---:|:---:|:---:|
| Indexing | 1-based | 0-based | 0-based | 1-based |
| `removeOS` | `false` | `True` | `False` | `false` |
| `regrid` | `false` | `True` | `False` | `false` |

### Syntax

| | mapVBVD | pymapVBVD | twixtools | MRITwixTools.jl |
|:---|:---|:---|:---|:---|
| Read data | `twix.image()` | `twix.image['']` | loop over `mdb` list | `getdata(twix.image)` |
| Slice data | `twix.image(:,:,1)` | `twix.image[:,:,0]` | — | `twix.image[:,:,1]` |
| Squeeze | `twix.image{''}` | `.squeeze = True` | manual | `.squeeze = true` |
| Set flag | `.flagRemoveOS = 1` | `.flagRemoveOS = True` | `.flags['remove_os']` | `.removeOS = true` |
| Header | `hdr.MeasYaps` (struct) | `hdr.MeasYaps[tuple]` | `hdr['MeasYaps']` | `hdr.MeasYaps.sKSpace...` |
| Search | — | `search_header_for_keys` | — | `search(hdr, terms...)` |

### Feature Support

| | mapVBVD | pymapVBVD | twixtools | MRITwixTools.jl |
|:---|:---:|:---:|:---:|:---:|
| Write support | — | — | ✓ | — |
| Low-level mdb access | — | — | ✓ | — |
| Multi-raid (VD/VE/XA) | ✓ | ✓ | ✓ | ✓ |

## Dependencies

- [FFTW.jl](https://github.com/JuliaMath/FFTW.jl) — FFT for oversampling removal
- [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) — Ramp sample regridding
- [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) — Progress bars

## Credits

This is a native Julia port of the Python [pymapVBVD](https://github.com/wtclarke/pymapvbvd) by Will Clarke, which is itself a port of Philipp Ehses' original Matlab [mapVBVD](https://github.com/pehses/mapVBVD). See also Philipp Ehses' [twixtools](https://github.com/pehses/twixtools), which provides reading, writing, and low-level mdb access for twix files in Python.

Released under the MIT License.

[docs-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-url]: https://JakobAsslaender.github.io/MRITwixTools.jl/stable
[ci-img]: https://github.com/JakobAsslaender/MRITwixTools.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/JakobAsslaender/MRITwixTools.jl/actions
[docs-ci-img]: https://github.com/JakobAsslaender/MRITwixTools.jl/workflows/Documentation/badge.svg
[docs-ci-url]: https://github.com/JakobAsslaender/MRITwixTools.jl/actions