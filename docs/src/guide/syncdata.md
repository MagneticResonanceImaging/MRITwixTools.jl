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

## Discovering the ASCII Tags in a Packet

If you don't know the tag string that identifies a packet, the exported
helper [`syncdata_strings`](@ref) walks a packet and returns every run of
consecutive printable-ASCII bytes (`0x20..0x7E`, whitespace/control bytes
excluded), together with their byte offsets:

```julia
using MRITwixTools
twx = read_twix("meas.dat")
for s in syncdata_strings(twx.syncdata[1]; min_length = 16)
    println(@sprintf("  @%6d  len=%-4d  %s", s.offset, s.length, s.str))
end
```

A typical output looks like:

```
  @     8  len=8     PMUData_v1
  @    24  len=4     SEQD
  ...
```

For a quick tour of a scan, use [`summarize_syncdata`](@ref):

```julia
summarize_syncdata(twx.syncdata; min_length = 16)
```

The `min_length` keyword controls how many consecutive printable bytes
qualify as an "ASCII run". Two kinds of noise typically show up if it is
set too low:

- Some Siemens SEQData framing packets carry short trailing fragments of
  the ASCII XProtocol header (e.g. `"<Comment>"`, `"<Dependency>"`,
  `<Context> "NORMAL"`). Because the XProtocol string spans packet
  boundaries, only ~10–20 characters of it survive as a run in any single
  packet — a `min_length` of 20–32 hides all of them.
- The bit patterns of small-magnitude `Float32` numbers cluster around
  `0x3E..0x3F` (bytes `>` and `?`), which fall in the printable-ASCII
  range. Sequences of small floats therefore occasionally produce short
  "ASCII runs" that are pure noise (typically ≤ ~12 chars).

A versioned tag like `"SpiralGradShape_v1"` is usually 15–30 characters
long, so choosing `min_length` at ~16 gives a good signal-to-noise ratio.
If your tag is shorter, drop `min_length` and inspect the output — real
tags tend to appear in exactly one packet at a fixed, small offset, while
noise fluctuates in offset from one packet to the next.

SYNCDATA streams are usually dominated by two kinds of noisy packets:

1. **Silent framing packets** (PMU telemetry, timing frames, …) with no
   printable-ASCII content at all.
2. **XProtocol-fragment packets** whose trailing bytes carry a slice of
   the ASCII XProtocol header — producing ASCII runs at offsets *near
   the end* of the packet.

`summarize_syncdata` hides both categories by default and reports them
in a single aggregate line at the end, keeping the output focused on
packets that plausibly carry a sequence tag:

- Packets with no qualifying ASCII run are omitted (case 1).
- Packets whose runs *all* start past `max_start_frac × length(pkt)`
  (default `0.5`) are omitted as "late-only" (case 2). Sequence tags
  that identify a payload are almost always near the *start* of their
  packet, so the heuristic reliably keeps them visible.

To disable one of these filters:

- `show_empty = true` — list every packet, including silent ones.
- `max_start_frac = 1.0` — do not treat late-only packets as noise.

Once you know the tag, use [`payload_offset`](@ref) to jump straight to
the first byte that is *not* printable ASCII after that tag — i.e. the
plausible start of the binary payload:

```julia
p = payload_offset(pkt, "PMUData_v1")   # 1-based index into `pkt`, or `nothing`
```

The helper skips *all* trailing printable bytes past the tag, so if the
tag is immediately followed by another ASCII field name it will keep
sliding. Sequence-specific parsers usually still need to skip a few extra
NUL / framing bytes past this offset until the parsed fields look
plausible — see the pattern below.

!!! note "When it can go wrong"
    Auto-splitting a packet by "where do the printable characters end?"
    works whenever the binary payload is dominated by non-printable bytes
    (small integers, floats near zero, etc.). It is not reliable if the
    payload itself contains a long printable-ASCII string — that string
    would be reported as its own ASCII run. Manual inspection with
    `summarize_syncdata` remains the safest first step for a new format.

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

## API

The full docstrings for the SYNCDATA helpers live in the
[API Reference](api.md#SYNCDATA-Introspection):

- [`syncdata_strings`](@ref)
- [`payload_offset`](@ref)
- [`summarize_syncdata`](@ref)

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