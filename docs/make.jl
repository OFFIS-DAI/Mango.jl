# see documentation at https://juliadocs.github.io/Documenter.jl/stable/

using Documenter, Mango

makedocs(
    modules=[Mango],
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    authors="mango Team",
    sitename="Mango.jl",
    pages=Any["Home" => "index.md",
              "Agents" => "agent.md",
              "Container" => "container.md",
              "Scheduling" => "scheduling.md",]
    repo = "https://gitlab.com/mango-agents/Mango.jl",
)
