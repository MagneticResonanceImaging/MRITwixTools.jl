# Internal API Reference

These functions are not exported but may be useful for advanced usage or are documented here for contributor reference.

## MDH Parsing

```@docs
MRITwixTools.compute_dims!
MRITwixTools.readMDH!
MRITwixTools.tryAndFixLastMdh!
MRITwixTools.calcIndices
MRITwixTools.calcRange
MRITwixTools.readData
```

## Data Helpers

```@docs
MRITwixTools.fixLoopCounter!
MRITwixTools.average_dim
MRITwixTools.loop_counter
MRITwixTools.dim_extent
```

## Header Parsing

```@docs
MRITwixTools.parse_ascconv
MRITwixTools.parse_xprot
MRITwixTools.parse_buffer
```

## Utilities

```@docs
MRITwixTools.cumtrapz
```