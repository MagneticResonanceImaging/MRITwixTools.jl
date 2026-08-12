# SYNCDATA Payloads

Siemens `.dat` files can contain MDH packets tagged with the `MDH_SYNCDATA`
bit (bit 5 of `evalInfoMask`). Their contents are not part of the k-space
data stream — they carry auxiliary information such as:

- Physio / PMU (pulse-oximeter, ECG, respiration) traces,
- Coil-sensitivity adjustment (`AdjCoilSensSeq`) frames,
- Sequence-specific binary blobs written by custom pulse sequences
  (precomputed gradient shapes, k-space trajectories, ...).

Because the layout is entirely sequence-specific, MRITwixTools does **not**
parse SYNCDATA payloads. Instead, if a scan contains any SYNCDATA packets,
their raw payload bytes (everything *after* the MDH header) are collected
into a `Vector{Vector{UInt8}}` and stored on the `TwixObj` under the key
`"syncdata"`.

## Access

```julia
twx = read_twix("meas.dat")

# Present only if the scan actually contains SYNCDATA packets
if haskey(getfield(twx, :_data), "syncdata")
    sync = twx.syncdata           # ::Vector{Vector{UInt8}}
    @show length(sync)            # number of packets
    @show sum(length, sync)       # total bytes
    @show length.(sync[1:min(5,end)])
end
```

The `show` method of `TwixObj` lists SYNCDATA with a summary line, e.g.:

```
TwixObj
  📋 hdr
  📊 image (327680 acq, size [128, 32, 128, 128])
  🧬 syncdata (1798 packet(s), 3122000 bytes)
```

For multi-raid files, `read_twix` returns a `Vector{TwixObj}` and each
element may independently carry its own `syncdata` (or not).

## Parsing a Sequence-Specific Payload

Most custom payloads are introduced by an ASCII tag (a version-stamped
sequence-specific string). To locate and parse one, iterate over packets
and use `findfirst` to locate the tag inside the raw bytes:

```julia
tag = Vector{UInt8}(codeunits("MyCustomTag"))
for pkt in twx.syncdata
    r = findfirst(tag, pkt)
    r === nothing && continue

    # Bytes immediately after the tag — parse whatever layout the sequence uses.
    # For example, if the payload is  Float64, Int32, Int32, Float32[N], ...
    p = last(r) + 1                                          # 1-based index
    a  = reinterpret(Float64, pkt[p    : p + 7 ])[1]
    b  = reinterpret(Int32,   pkt[p + 8: p + 11])[1]
    c  = reinterpret(Int32,   pkt[p +12: p + 15])[1]
    # ...
    break
end
```

!!! note "Padding / framing bytes"
    Siemens wraps custom payloads in an `sSYNCDATA` / `SEQData` frame, so
    a few bytes usually sit between the tag and the start of the actual
    binary layout. A simple robust pattern is to slide forward `skip = 0..256`
    bytes after the tag until the first candidate header parses to
    plausible values (finite floats, positive lengths that fit in the
    packet). See
    [`examples/read_spiral_gradshape.jl`](https://github.com/MagneticResonanceImaging/MRITwixTools.jl/blob/main/examples/read_spiral_gradshape.jl)
    in the repository for a complete worked example that handles this.

## Complete Example: `SpiralGradShape`

A pulse sequence writes a spiral gradient shape into SYNCDATA with the
following layout after the ASCII tag `SpiralGradShape`:

| Type      | Field         |
|-----------|---------------|
| `Float64` | `dMax_Ampl`   |
| `Int32`   | `lGradLength` |
| `Int32`   | `lROLength`   |
| `Float32[lGradLength]` | `X` |
| `Float32[lGradLength]` | `Z` |

```julia
using MRITwixTools

const TAG = Vector{UInt8}(codeunits("SpiralGradShape"))

function read_spiral_gradshape(filename; max_skip = 256)
    twx = read_twix(filename; verbose = false)
    scans = twx isa AbstractVector ? twx : [twx]

    for t in scans
        haskey(getfield(t, :_data), "syncdata") || continue
        for pkt in t.syncdata
            r = findfirst(TAG, pkt)
            r === nothing && continue

            after_tag = last(r) + 1
            for skip in 0:max_skip
                p = after_tag + skip
                p + 15 > length(pkt) && break

                dMax  = reinterpret(Float64, pkt[p     : p + 7 ])[1]
                nGrad = reinterpret(Int32,   pkt[p + 8 : p + 11])[1]
                nRO   = reinterpret(Int32,   pkt[p + 12: p + 15])[1]

                (isfinite(dMax) && 0 < abs(dMax) < 1e6 &&
                 1 <= nGrad <= 10_000_000 && 1 <= nRO <= 10_000_000) || continue

                need = 2 * Int64(nGrad) * sizeof(Float32)
                p + 15 + need > length(pkt) && continue

                xs = p + 16
                zs = xs + nGrad * sizeof(Float32)
                X = collect(reinterpret(Float32, pkt[xs : xs + nGrad*4 - 1]))
                Z = collect(reinterpret(Float32, pkt[zs : zs + nGrad*4 - 1]))

                return (; dMaxAmpl = dMax,
                          lGradLength = Int(nGrad),
                          lROLength   = Int(nRO),
                          X = X, Z = Z)
            end
        end
    end
    error("No plausible SpiralGradShape payload found in $filename")
end

s = read_spiral_gradshape("meas.dat")
@show s.dMaxAmpl s.lGradLength s.lROLength
@show maximum(abs, s.X)  maximum(abs, s.Z)
```

## Implementation Notes

- SYNCDATA payload bytes are extracted directly during the MDH scan pass in
  `loop_mdh_read`. The reader saves the file position, reads
  `ulDMALength - byteMDH` bytes, and seeks back so the surrounding
  skip-based MDH loop advancement is not disturbed.
- The `"syncdata"` entry is stored on the `TwixObj` only when the scan
  actually produced at least one SYNCDATA packet; it is not present
  otherwise. Use `haskey(getfield(twx, :_data), "syncdata")` to test.
- Post-MDH processing (`tryAndFixLastMdh!`, `compute_dims!`) checks for
  `RawData` explicitly and skips the `syncdata` entry.
- The `TwixObj` type-narrowing helper `_twixobj_val` returns
  `Union{TwixHdr, RawData, Vector{Vector{UInt8}}}`, which preserves REPL
  tab-completion even when `syncdata` is present.