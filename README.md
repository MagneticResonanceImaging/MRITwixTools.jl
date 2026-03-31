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

## Usage

```julia
using MapVBVD

# Read a twix file
twixObj = mapVBVD("meas_MID00305.dat")

# For multi-raid files (VD+), twixObj is a Vector{TwixObj}
# For single files (VB), it is a single TwixObj

# Access image data
twixObj.image.flagRemoveOS = true
data = getdata(twixObj.image)  # returns full data array

# Or with slicing (1-based Julia indexing)
data = twixObj.image[1:128, :, :]

# Check available MDH flags
flags = MDH_flags(twixObj)

# Access header
hdr = twixObj.hdr

# Search header keys
keys = search_header_for_keys(twixObj, ("sTXSPEC", "asNucleusInfo"), top_lvl="MeasYaps")

# Get header values
vals = search_header_for_val(twixObj, "MeasYaps", ("sTXSPEC", "asNucleusInfo", "0", "tNucleus"))
```

## Flags

Control data processing with the following flags:

```julia
twixObj.image.flagRemoveOS = true          # Remove oversampling
twixObj.image.flagRampSampRegrid = true     # Ramp sample regridding
twixObj.image.flagDoAverage = true          # Average across averages
twixObj.image.flagAverageReps = true        # Average across repetitions
twixObj.image.flagAverageSets = true        # Average across sets
twixObj.image.flagIgnoreSeg = true          # Ignore segments
twixObj.image.flagSkipToFirstLine = false   # Don't skip to first line
twixObj.image.flagDisableReflect = false    # Don't disable line reflection
twixObj.image.squeeze = true               # Squeeze singleton dimensions
```

## Differences from Python version

- **1-based indexing**: All array indices are 1-based (Julia convention)
- **Data access**: Use `getdata(obj)` instead of `obj['']`, or `obj[ranges...]` for sliced access
- **Properties**: Flag properties use Julia's `setproperty!` syntax: `obj.flagRemoveOS = true`
- **Header search**: Use `search_header_for_keys(twixObj, terms)` instead of `twixObj.search_header_for_keys(terms)`
- **MDH flags**: Use `MDH_flags(twixObj)` instead of `twixObj.MDH_flags()`

## Dependencies

- [FFTW.jl](https://github.com/JuliaMath/FFTW.jl) — FFT for oversampling removal
- [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) — Ramp sample regridding
- [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) — Progress bars

## Credits

This is a native Julia port of the Python [pymapVBVD](https://github.com/wtclarke/pymapvbvd) by Will Clarke, which is itself a port of Philipp Ehses' original Matlab [mapVBVD](https://github.com/pehses/mapVBVD).

Released under the MIT License.