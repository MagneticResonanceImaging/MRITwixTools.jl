# MapVBVD.jl

Native Julia port of the [pymapVBVD](https://github.com/wtclarke/pymapvbvd) / Matlab [mapVBVD](https://github.com/pehses/mapVBVD) tool for reading Siemens raw MRI data (twix `.dat` files).

Supports both VB and VD/VE software versions.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/<your-repo>/MapVBVD.jl")
```

Or in development mode:
```julia
Pkg.develop(path="/path/to/MapVBVD.jl")
```

## Quick Start

```julia
using MapVBVD

# Read a twix file (returns raw data by default — no processing)
twixObj = mapVBVD("meas_MID00305.dat")

# For multi-raid files (VD+), twixObj is a Vector{TwixObj}
# For single files (VB), it is a single TwixObj

# Read image data
data = getdata(twixObj.image)

# Or with slicing (1-based Julia indexing)
data = twixObj.image[1:128, :, :]

# Check available scan types
MDH_flags(twixObj)  # e.g. ["image", "noise", "refscan"]
```

## Processing Options

By default, `mapVBVD` returns raw data with no processing. Enable processing either at load time or afterwards:

```julia
# At load time
twixObj = mapVBVD("meas.dat", removeOS=true, squeeze=true)

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

# Search across all header sections
search(hdr, "lBaseRes")
# => ["MeasYaps.sKSpace.lBaseResolution" => 256.0,
#     "Phoenix.sKSpace.lBaseResolution" => 128.0]

# Search with multiple terms (AND logic)
search(hdr, "sTXSPEC", "Nucleus")
# => ["MeasYaps.sTXSPEC.asNucleusInfo.0.tNucleus" => "\"1H\""]

# List all leaf values
leaves(hdr)
```

## Differences from Python/Matlab versions

- **1-based indexing**: All array indices are 1-based (Julia convention)
- **No processing by default**: `removeOS` and `regrid` default to `false`
- **Data access**: Use `getdata(obj)` or `obj[ranges...]`
- **Direct flag access**: `obj.removeOS = true` (no `flag` prefix needed)
- **Header search**: `search(hdr, "term")` returns `["dotted.path" => value]` pairs
- **MDH flags**: `MDH_flags(twixObj)` (free function, not method)

## Dependencies

- [FFTW.jl](https://github.com/JuliaMath/FFTW.jl) — FFT for oversampling removal
- [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) — Ramp sample regridding
- [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) — Progress bars

## Credits

This is a native Julia port of the Python [pymapVBVD](https://github.com/wtclarke/pymapvbvd) by Will Clarke, which is itself a port of Philipp Ehses' original Matlab [mapVBVD](https://github.com/pehses/mapVBVD).

Released under the MIT License.