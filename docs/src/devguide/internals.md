# Internal API Reference

These functions are not exported but may be useful for advanced usage or are documented here for contributor reference.

## MDH Parsing

```@docs
MapVBVD.compute_dims!
MapVBVD.readMDH!
MapVBVD.tryAndFixLastMdh!
MapVBVD.calcIndices
MapVBVD.calcRange
MapVBVD.readData
```

## Data Helpers

```@docs
MapVBVD.fixLoopCounter!
MapVBVD.average_dim
MapVBVD.loop_counter
MapVBVD.dim_extent
```

## Header Parsing

```@docs
MapVBVD.parse_ascconv
MapVBVD.parse_xprot
MapVBVD.parse_buffer
```

## Utilities

```@docs
MapVBVD.cumtrapz
```