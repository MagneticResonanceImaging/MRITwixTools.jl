# [API Reference](@id API-Reference)

## Entry Point

```@docs
read_twix
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

These are exported convenience functions that set processing flags on a [`MRITwixTools.RawData`](@ref) object.
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

## SYNCDATA Introspection

These utilities help discover the ASCII tags embedded in an MDH_SYNCDATA
packet and locate the start of the binary payload that follows a tag.
See the [SYNCDATA Payloads](syncdata.md) guide for context.

```@docs
syncdata_strings
payload_offset
summarize_syncdata
```

## Header Navigation

```@docs
NestedDict
search
leaves
setpath!
```

## Types

```@docs
MRITwixTools.TwixObj
MRITwixTools.TwixHdr
MRITwixTools.RawData
MRITwixTools.ReadInfo
MRITwixTools.AcquisitionMeta
MRITwixTools.DimSizes
```