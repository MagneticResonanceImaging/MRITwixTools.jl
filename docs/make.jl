using Documenter
using MapVBVD

makedocs(
    sitename = "MapVBVD.jl",
    modules  = [MapVBVD],
    remotes  = nothing,
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        repolink   = "https://github.com/JakobAsslaender/MapVBVD.jl",
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
    repo = "github.com/JakobAsslaender/MapVBVD.jl.git",
    devbranch = "main",
)