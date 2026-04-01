# Installation

## Requirements

- Julia 1.9 or later

## From a Git Repository

```julia
using Pkg
Pkg.add(url="https://github.com/JakobAsslaender/MapVBVD.jl")
```

## Development Mode

For local development or contributing:

```julia
using Pkg
Pkg.develop(path="/path/to/MapVBVD.jl")
```

## Dependencies

MapVBVD.jl depends on:

| Package | Purpose |
|---------|---------|
| [FFTW.jl](https://github.com/JuliaMath/FFTW.jl) | FFT for oversampling removal |
| [Interpolations.jl](https://github.com/JuliaMath/Interpolations.jl) | Ramp-sample regridding |
| [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl) | Progress bars during data reading |

All dependencies are installed automatically.