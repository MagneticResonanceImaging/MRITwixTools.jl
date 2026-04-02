# Installation

## Requirements

- Julia 1.9 or later

## From the Julia Registry

```julia
using Pkg
Pkg.add("MRITwixTools")
```

## Development Mode

For local development or contributing:

```julia
using Pkg
Pkg.develop("MRITwixTools")
```

## Dependencies

MRITwixTools.jl depends on:

| Package | Purpose |
|---------|---------|
| [FFTW.jl](https://github.com/JuliaMath/FFTW.jl) | FFT for oversampling removal |
| [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) | Ramp-sample regridding |
| [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) | Progress bars during data reading |

All dependencies are installed automatically.