# MRITwixTools.jl

Native Julia package for reading Siemens MRI raw data (twix `.dat` files).

A port of the Python packages [twixtools](https://github.com/pehses/twixtools) and [pymapVBVD](https://github.com/wtclarke/pymapvbvd), and the Matlab package [mapVBVD](https://github.com/pehses/mapVBVD), supporting both VB and VD/VE/XA software versions.

## Installation

```julia
using Pkg
Pkg.add("MRITwixTools")
```

Or in development mode:

```julia
Pkg.develop("MRITwixTools")
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
| Tab completion | first level | first level | first level | every level |
| Write support | — | — | ✓ | — |
| Low-level mdb access | — | — | ✓ | — |
| Multi-raid (VD/VE/XA) | ✓ | ✓ | ✓ | ✓ |

## Package Overview

```
read_twix("file.dat")
  │
  ├── TwixObj
  │     ├── .hdr     → TwixHdr (nested header tree with tab-completion)
  │     ├── .image   → RawData (image acquisitions)
  │     ├── .noise   → RawData (noise adjustments)
  │     ├── .refscan → RawData (GRAPPA reference lines)
  │     └── ...      → RawData (other scan types)
  │
  └── Vector{TwixObj}   (for multi-raid VD/VE/XA files)
```

## User Guide

- [Installation](guide/installation.md) — Prerequisites and install methods
- [Header Access](guide/headers.md) — Navigating header trees with tab-completion
- [Data Access](guide/data_access.md) — Reading, slicing, and processing scan data
- [API Reference](guide/api.md) — Complete exported function listing

## Developer Guide

- [Contributing](devguide/contributing.md) — Development setup and PR guidelines
- [Architecture](devguide/architecture.md) — Codebase walkthrough and design notes
- [Tab-Completion Internals](devguide/tab_completion.md) — How deep REPL completion works
- [Internal API](devguide/internals.md) — Non-exported functions reference