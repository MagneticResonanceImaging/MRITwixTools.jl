# ─── SYNCDATA payload introspection utilities ───────────────────────────
#
# The bytes inside a SYNCDATA packet are entirely sequence-specific and
# MRITwixTools does not attempt to parse them. The helpers below only look
# at printable-ASCII structure of a packet — they let a caller discover
# which ASCII tags are present and, given a tag, where the following
# binary payload starts. Any interpretation of the payload itself is up
# to the caller.

"""
    is_printable_ascii(b::UInt8) -> Bool

Return `true` if byte `b` is a printable ASCII character (0x20..0x7E).
Whitespace / control bytes (including `\\n`, `\\t`) are treated as
non-printable so that adjacent ASCII names remain visible as separate
runs.
"""
@inline is_printable_ascii(b::UInt8) = 0x20 <= b <= 0x7E

"""
    syncdata_strings(pkt::AbstractVector{UInt8}; min_length::Int = 4)
        -> Vector{@NamedTuple{offset::Int, length::Int, str::String}}

Return every run of ≥ `min_length` consecutive printable-ASCII bytes in
`pkt`. Each entry is a `NamedTuple` with fields

- `offset` — 0-based byte offset of the first character in `pkt`,
- `length` — number of characters in the run,
- `str`    — the run itself as a `String`.

SYNCDATA packets typically contain a small number of short ASCII field
names (Siemens SEQData framing, such as `"SQ"`, `"AdjCoilSensSeq"`,
`"PMUData"`) followed by one or more sequence-specific tags
(e.g. `"MyCustomTag_v1"`) that mark the beginning of a binary payload. A
call like

```julia
syncdata_strings(pkt; min_length = 16)
```

typically hides the framing noise and shows only the meaningful tag(s).

!!! note "False-positive runs"
    The byte-level `is_printable_ascii` predicate can produce
    short-but-not-meaningful runs in two situations:

    - Fragments of the ASCII XProtocol header may bleed into fixed-size
      SEQData framing packets. Because the string spans packet boundaries,
      only ~10–20 characters survive as a run inside any one packet.
    - Small-magnitude `Float32` values pack their exponent bytes into
      `0x3E..0x3F` (bytes `>` / `?`), so vectors of small floats
      occasionally produce ASCII runs up to ~12 characters long.

    A `min_length` of 16 or above hides both. If you don't know the tag
    length in advance, sweep `min_length` downwards — genuine tags appear
    in exactly one packet at a stable offset, while noise fluctuates.
"""
function syncdata_strings(pkt::AbstractVector{UInt8}; min_length::Int = 4)
    out = @NamedTuple{offset::Int, length::Int, str::String}[]
    n = length(pkt)
    i = 1
    @inbounds while i <= n
        if is_printable_ascii(pkt[i])
            j = i
            while j <= n && is_printable_ascii(pkt[j])
                j += 1
            end
            len = j - i
            if len >= min_length
                push!(out, (offset = i - 1, length = len,
                            str = String(copy(pkt[i:j-1]))))
            end
            i = j
        else
            i += 1
        end
    end
    return out
end

"""
    payload_offset(pkt::AbstractVector{UInt8}, tag::AbstractString;
                   min_padding::Int = 0, max_padding::Int = 256)
        -> Union{Int, Nothing}

Locate the ASCII `tag` inside `pkt` and return the 1-based byte offset of
the first *non-printable* byte after it (i.e. the first byte that is not
ASCII 0x20..0x7E). This is a good proxy for "where the binary payload
starts" when the tag is followed by some padding of NUL bytes / framing.

`min_padding` / `max_padding` bound how far to search past the tag; the
search stops as soon as a non-printable byte is found. Returns `nothing`
if `tag` is not present in `pkt` or the packet ends before a non-printable
byte is encountered.

Because Siemens sometimes inserts a variable number of framing/padding
bytes between an ASCII tag and the actual binary header, callers that
know the exact binary layout usually still want to slide forward a few
bytes past this offset until the parsed fields look plausible — see the
SYNCDATA Payloads user guide for the recommended pattern.
"""
function payload_offset(pkt::AbstractVector{UInt8}, tag::AbstractString;
                         min_padding::Int = 0, max_padding::Int = 256)
    tagbytes = Vector{UInt8}(codeunits(tag))
    r = findfirst(tagbytes, pkt)
    r === nothing && return nothing

    # Position immediately after the last byte of the tag (1-based).
    p = last(r) + 1
    n = length(pkt)

    # Skip further printable-ASCII bytes (e.g. framing continues past the tag).
    while p <= n && is_printable_ascii(pkt[p])
        p += 1
    end

    stop = min(n, p + max_padding)
    p = min(p + min_padding, stop + 1)
    return p <= n ? p : nothing
end

"""
    summarize_syncdata(sync::AbstractVector{<:AbstractVector{UInt8}};
                        min_length::Int = 4,
                        max_start_frac::Float64 = 0.5,
                        show_empty::Bool = false,
                        io::IO = stdout)

Print a human-readable summary of the packets in `sync` (as returned by
`TwixObj.syncdata`): the packet index, total size in bytes, and every ASCII
run of length ≥ `min_length` together with its offset.

Many SYNCDATA streams are dominated by:

1. **Framing packets** (PMU telemetry, timing frames, …) that carry no
   printable-ASCII content at all, and
2. **XProtocol-fragment packets** — fixed-size Siemens SEQData frames
   whose *trailing* bytes contain a slice of the ASCII XProtocol header,
   producing short ASCII runs at offsets near the *end* of the packet.

Both kinds of noise are hidden by default:

- Packets with no qualifying ASCII run are omitted (this handles case 1).
- Packets whose runs all start past `max_start_frac × length(pkt)` are
  omitted as "late-only" runs (this handles case 2). Custom tags
  identifying a payload are almost always near the *start* of their
  packet, so `max_start_frac = 0.5` (the default) keeps them visible
  while dropping trailing XProtocol fragments.

A single aggregate line at the end reports how many packets were hidden
and for what reason. Set `max_start_frac = 1.0` to disable the
"late-only" filter, and `show_empty = true` to list every packet
individually.

```julia
twx = read_twix("meas.dat")
MRITwixTools.summarize_syncdata(twx.syncdata; min_length = 16)
```
"""
function summarize_syncdata(sync::AbstractVector{<:AbstractVector{UInt8}};
                             min_length::Int = 4,
                             max_start_frac::Float64 = 0.5,
                             show_empty::Bool = false,
                             io::IO = stdout)
    n_total = length(sync)
    n_empty = 0
    n_late = 0
    empty_sizes = Dict{Int, Int}()
    late_sizes  = Dict{Int, Int}()

    println(io, "SYNCDATA: ", n_total, " packet(s), ",
            sum(length, sync; init = 0), " bytes total")

    for (i, pkt) in enumerate(sync)
        strs = syncdata_strings(pkt; min_length = min_length)
        if isempty(strs)
            n_empty += 1
            empty_sizes[length(pkt)] = get(empty_sizes, length(pkt), 0) + 1
            if show_empty
                println(io, "packet ", i, " (", length(pkt), " bytes):")
                println(io, "    (no ASCII runs of length >= ", min_length, ")")
            end
            continue
        end

        # "Late-only" packets: every ASCII run starts past max_start_frac
        # of the packet length. These are typical XProtocol-fragment frames.
        threshold = max_start_frac * length(pkt)
        if !show_empty && max_start_frac < 1.0 &&
           all(s.offset >= threshold for s in strs)
            n_late += 1
            late_sizes[length(pkt)] = get(late_sizes, length(pkt), 0) + 1
            continue
        end

        println(io, "packet ", i, " (", length(pkt), " bytes):")
        for s in strs
            @printf(io, "    @%6d  len=%-4d  %s\n",
                    s.offset, s.length, s.str)
        end
    end

    if !show_empty && (n_empty > 0 || n_late > 0)
        parts = String[]
        if n_empty > 0
            sizes = join(["$c×$sz B" for (sz, c) in sort(collect(empty_sizes),
                                                          by = first)], ", ")
            push!(parts, "$(n_empty) with no ASCII run of length >= $(min_length) ($sizes)")
        end
        if n_late > 0
            sizes = join(["$c×$sz B" for (sz, c) in sort(collect(late_sizes),
                                                          by = first)], ", ")
            pct = round(Int, 100 * max_start_frac)
            push!(parts, "$(n_late) with ASCII runs only in the last $(100-pct)% ($sizes)")
        end
        println(io, "(hidden: ", join(parts, "; "),
                ". Pass show_empty=true or max_start_frac=1.0 to see them.)")
    end
    return nothing
end