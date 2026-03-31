module MapVBVD

using FFTW
using Interpolations
using Printf
using ProgressMeter

# Core data structures
include("nested_dict.jl")
include("mdh_constants.jl")
include("types.jl")

# Functionality
include("read_twix_hdr.jl")
include("twix_map_obj.jl")
include("mapVBVD_main.jl")

# Keep old name as alias for backward compatibility
const TwixMapObj = ScanData

# Public API
export mapVBVD
export fullSize, dataSize, sqzSize, sqzDims, getdata, unsorted
export MDH_flags, search_header_for_keys, search_header_for_val
export set_flagRemoveOS!, set_flagRampSampRegrid!, set_flagDoAverage!
export set_flagAverageReps!, set_flagAverageSets!, set_flagIgnoreSeg!
export set_flagSkipToFirstLine!, set_flagDisableReflect!

# New API exports
export NestedDict, search, leaves, setpath!

end # module
