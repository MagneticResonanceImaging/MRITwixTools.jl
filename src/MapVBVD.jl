module MapVBVD

using FFTW
using Interpolations
using Printf
using ProgressMeter

# Sub-modules / includes
include("attrdict.jl")
include("read_twix_hdr.jl")
include("twix_map_obj.jl")
include("mapVBVD_main.jl")

# Public API
export mapVBVD, fullSize, dataSize, sqzSize, sqzDims, getdata, unsorted
export MDH_flags, search_header_for_keys, search_header_for_val
export set_flagRemoveOS!, set_flagRampSampRegrid!, set_flagDoAverage!
export set_flagAverageReps!, set_flagAverageSets!, set_flagIgnoreSeg!
export set_flagSkipToFirstLine!, set_flagDisableReflect!

end # module