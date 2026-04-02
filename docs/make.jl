using Pkg
Pkg.activate(Base.source_dir())
Pkg.develop(PackageSpec(path=pwd()))
Pkg.instantiate()
using Documenter
using MRITwixTools

makedocs(
    sitename = "MRITwixTools.jl",
    modules  = [MRITwixTools],
    remotes  = nothing,
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        repolink   = "https://github.com/MagneticResonanceImaging/MRITwixTools.jl",
        edit_link  = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "User Guide" => [
            "Installation"  => "guide/installation.md",
            "Header Access" => "guide/headers.md",
            "Data Access"   => "guide/data_access.md",
            "API Reference" => "guide/api.md",
        ],
        "Developer Guide" => [
            "Contributing"            => "devguide/contributing.md",
            "Architecture"            => "devguide/architecture.md",
            "Tab-Completion Internals" => "devguide/tab_completion.md",
            "Internal API"            => "devguide/internals.md",
        ],
    ],
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/MagneticResonanceImaging/MRITwixTools.jl.git",
    devbranch = "main",
)