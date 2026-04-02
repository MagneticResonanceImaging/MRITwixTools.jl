# Data Access

## Reading Data

After loading a twix file, access scan data through the `RawData` objects stored on the `TwixObj`:

```julia
twixObj = read_twix("meas.dat")

# Full data read
data = getdata(twixObj.image)

# Or equivalently, using indexing syntax
data = twixObj.image[:, :, :]
```

## Scan Types

A twix file can contain multiple scan types. Use [`MDH_flags`](@ref) to see which ones have data:

```julia
MDH_flags(twixObj)
# => ["image", "noise", "refscan", "phasecor"]
```

Common scan types:

| Type | Description |
|------|-------------|
| `image` | Primary image acquisitions |
| `noise` | Noise adjustment scans |
| `refscan` | GRAPPA/ACS reference lines |
| `refscanPC` | Phase correction reference scans |
| `phasecor` | EPI phase correction navigators |
| `phasestab` | Phase stabilization scans |

Access each via dot syntax: `twixObj.image`, `twixObj.noise`, `twixObj.refscan`, etc.

## The 16-Dimension Data Model

Siemens raw data is organized into 16 dimensions:

| Index | Name | Description |
|-------|------|-------------|
| 1 | `Col` | Readout (columns / samples) |
| 2 | `Cha` | Receive channels (coils) |
| 3 | `Lin` | Phase-encoding lines |
| 4 | `Par` | 3D partition encodes |
| 5 | `Sli` | Slices |
| 6 | `Ave` | Averages |
| 7 | `Phs` | Phases (cardiac, etc.) |
| 8 | `Eco` | Echoes |
| 9 | `Rep` | Repetitions |
| 10 | `Set` | Sets |
| 11 | `Seg` | Segments (EPI interleaves) |
| 12–16 | `Ida`–`Ide` | Free indices |

Inspect dimensions with:

```julia
fullSize(twixObj.image)   # all 16 dimensions
# => [4096, 32, 128, 1, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

dataSize(twixObj.image)   # accounts for removeOS and averaging
sqzSize(twixObj.image)    # non-singleton dimensions only
# => [4096, 32, 128, 5]

sqzDims(twixObj.image)    # names of non-singleton dimensions
# => ["Col", "Cha", "Lin", "Sli"]
```

## Slicing / Indexing

Use standard Julia indexing on `RawData` objects:

```julia
# Read all data
data = twixObj.image[:, :, :]

# Read specific ranges (1-based indexing)
data = twixObj.image[1:128, :, :]

# Single index
data = twixObj.image[1, 2, :]
```

### Interaction with `squeeze`

When `squeeze = false` (default), indices map directly to the 16 dimensions:

```julia
twixObj.image.squeeze = false
data = twixObj.image[1:128, :, 1:64, :, 1:3, :, :, :, :, :, :, :, :, :, :, :]
#                    Col    Cha Lin    Par Sli ...
```

When `squeeze = true`, indices map to **non-singleton dimensions only**:

```julia
twixObj.image.squeeze = true
sqzDims(twixObj.image)  # => ["Col", "Cha", "Lin", "Sli"]

data = twixObj.image[1:128, :, 1:64, 1:3]
#                    Col    Cha Lin    Sli
```

This is much more convenient — you don't need to specify all 16 dimensions.

### Trailing Colon Behavior

A trailing `:` captures all remaining dimensions (similar to MATLAB):

```julia
twixObj.image.squeeze = true
# These are equivalent:
data = twixObj.image[1:128, :]     # Col=1:128, everything else
data = twixObj.image[1:128, :, :, :]  # Col=1:128, Cha=all, Lin=all, Sli=all
```

## Processing Flags

All processing flags default to `false` — MRITwixTools.jl returns raw, unprocessed data by default. Enable processing either at load time or afterwards:

```julia
# At load time
twixObj = read_twix("meas.dat", removeOS=true, squeeze=true)

# Or afterwards (triggers recomputation on next data read)
twixObj.image.removeOS = true
twixObj.image.squeeze = true
data = getdata(twixObj.image)
```

### Available Flags

| Flag | Default | Effect |
|------|---------|--------|
| `removeOS` | `false` | Remove 2× readout oversampling via FFT crop (halves `Col` dimension) |
| `regrid` | `false` | Ramp-sample regridding for non-Cartesian readouts (requires trajectory) |
| `doAverage` | `false` | Average across the `Ave` dimension |
| `averageReps` | `false` | Average across the `Rep` dimension |
| `averageSets` | `false` | Average across the `Set` dimension |
| `ignoreSeg` | `false` | Collapse the `Seg` dimension |
| `squeeze` | `false` | Drop singleton dimensions from returned arrays |
| `disableReflect` | `false` | Skip readout reflection (bipolar gradient) correction |
| `skipToFirstLine` | varies | Skip to first acquired k-space line (see below) |
| `ignoreROoffcenter` | `false` | Ignore readout off-center phase correction during regridding |

### `skipToFirstLine` Default Behavior

This flag has a scan-type-dependent default:

- **`image`** and **`phasestab`**: defaults to `false` (preserve full k-space extent)
- **All other scan types** (`noise`, `refscan`, etc.): defaults to `true` (skip unacquired leading lines)

This matters for partial-Fourier or GRAPPA reference scans where acquisition doesn't start at line 0.

### Backward-Compatible Flag Names

The old `flag`-prefixed names still work as aliases:

```julia
twixObj.image.flagRemoveOS = true     # same as twixObj.image.removeOS = true
twixObj.image.flagDoAverage = true    # same as twixObj.image.doAverage = true
twixObj.image.flagIgnoreSeg = true    # same as twixObj.image.ignoreSeg = true
```

The setter functions also remain available:

```julia
set_flagRemoveOS!(twixObj.image, true)
set_flagRampSampRegrid!(twixObj.image, true)  # errors if no trajectory available
```

## Processing Pipeline

When data is read (via `getdata` or indexing), the following processing steps are applied in order:

1. **Read raw data** from file at stored byte positions
2. **Reflection correction** — reverse readout for bipolar gradient lines (unless `disableReflect`)
3. **Regridding** — interpolate ramp-sampled readouts onto Cartesian grid (if `regrid`)
4. **Oversampling removal** — FFT → crop center half → IFFT (if `removeOS`)
5. **Range selection** — extract requested slice/index ranges
6. **Averaging** — accumulate and divide for averaged dimensions
7. **Squeeze** — drop singleton dimensions (if `squeeze`)

## Unsorted Data Access

For debugging or custom processing, read raw acquisitions without sorting into the k-space grid:

```julia
# All acquisitions as [NCol, NCha, NAcq]
raw = unsorted(twixObj.image)

# Single acquisition (by index)
acq = unsorted(twixObj.image, 42)
```