
using Documenter, Mango

makedocs(
    modules=[Mango],
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    authors="mango Team",
    sitename="Mango.jl",
    pages=Any["Home"=>"index.md",
        "Getting Started"=>"getting_started.md",
        "Agents"=>"agent.md",
        "Container"=>"container.md",
        "Roles"=>"role.md",
        "Simulation"=>"simulation.md",
        "Codecs"=>"encode_decode.md",
        "Scheduling"=>"scheduling.md",
        "Topologies"=>"topology.md",
        "Legals"=>"legals.md",],
    repo="https://github.com/OFFIS-DAI/Mango.jl",
)
deploydocs(
    repo="github.com/OFFIS-DAI/Mango.jl.git",
    push_preview=true
)