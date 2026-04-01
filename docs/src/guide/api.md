# [API Reference](@id API-Reference)

## Entry Point

```@docs
mapVBVD
```

## Data Access

```@docs
getdata
unsorted
fullSize
dataSize
sqzSize
sqzDims
MDH_flags
```

## Processing Flag Setters

These are exported convenience functions that set processing flags on a [`MapVBVD.RawData`](@ref) object.
Direct field access (e.g., `obj.removeOS = true`) is preferred for new code.

| Function | Equivalent |
|----------|------------|
| `set_flagRemoveOS!(obj, val)` | `obj.removeOS = val` |
| `set_flagRampSampRegrid!(obj, val)` | `obj.regrid = val` (errors if no trajectory) |
| `set_flagDoAverage!(obj, val)` | `obj.doAverage = val` |
| `set_flagAverageReps!(obj, val)` | `obj.averageReps = val` |
| `set_flagAverageSets!(obj, val)` | `obj.averageSets = val` |
| `set_flagIgnoreSeg!(obj, val)` | `obj.ignoreSeg = val` |
| `set_flagSkipToFirstLine!(obj, val)` | `obj.skipToFirstLine = val` |
| `set_flagDisableReflect!(obj, val)` | `obj.disableReflect = val` |

## Header Navigation

```@docs
NestedDict
search
leaves
setpath!
```

## Types

```@docs
MapVBVD.TwixObj
MapVBVD.TwixHdr
MapVBVD.RawData
MapVBVD.ReadInfo
MapVBVD.AcquisitionMeta
MapVBVD.DimSizes
```