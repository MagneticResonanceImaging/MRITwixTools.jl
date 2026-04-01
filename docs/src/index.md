# MapVBVD.jl

Native Julia package for reading Siemens MRI raw data (twix `.dat` files).

A port of the [pymapVBVD](https://github.com/wtclarke/pymapvbvd) / Matlab [mapVBVD](https://github.com/pehses/mapVBVD) tools, supporting both VB and VD/VE software versions.

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

## Differences from Python/Matlab Versions

| Feature | Python/Matlab | MapVBVD.jl |
|---------|--------------|------------|
| Indexing | 0-based | 1-based (Julia convention) |
| Default processing | `removeOS=true` | `removeOS=false` (raw data) |
| Data access | `twix["image"].data` | `getdata(twixObj.image)` or `twixObj.image[...]` |
| Flag access | `twix["image"].flagRemoveOS` | `twixObj.image.removeOS` (direct field) |
| Header search | `search_for_keys(hdr, terms)` → tuple keys | `search(hdr, terms...)` → `"dotted.path" => value` |
| Header access | `hdr["MeasYaps"][("sKSpace", "lBaseRes")]` | `hdr.MeasYaps.sKSpace.lBaseResolution` |
| Tab completion | First level only | Every level |
| MDH flags | Method on object | `MDH_flags(twixObj)` (free function) |

## Package Overview

```
mapVBVD("file.dat")
  │
  ├── TwixObj
  │     ├── .hdr     → TwixHdr (nested header tree with tab-completion)
  │     ├── .image   → ScanData (image acquisitions)
  │     ├── .noise   → ScanData (noise adjustments)
  │     ├── .refscan → ScanData (GRAPPA reference lines)
  │     └── ...      → ScanData (other scan types)
  │
  └── Vector{TwixObj}   (for multi-raid VD/VE files)
```

See the [Header Access](headers.md) page for working with headers, the [Data Access](data_access.md) page for reading and slicing scan data, and the [API Reference](api.md) for the complete function listing.