using Documenter
using MapVBVD

makedocs(
    sitename = "MapVBVD.jl",
    modules  = [MapVBVD],
    remotes  = nothing,
    format   = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        edit_link  = nothing,
    ),
    pages = [
        "Home"            => "index.md",
        "Header Access"   => "headers.md",
        "Data Access"     => "data_access.md",
        "Architecture"    => "architecture.md",
        "API Reference"   => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/your-username/MapVBVD.jl.git",
    devbranch = "main",
)