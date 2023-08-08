# see documentation at https://juliadocs.github.io/Documenter.jl/stable/

using Documenter, Mango

makedocs(
    modules=[Mango],
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    authors="mango Team",
    sitename="Mango.jl",
    pages=Any["Home" => "index.md",
              "Getting Started" => "getting_started.md",
              "Agents" => "agent.md",
              "Container" => "container.md",
              "Codecs" => "encode_decode.md",
              "Scheduling" => "scheduling.md",
              "Privacy" => "privacy.md",
              "Legals" => "legals.md",],
    repo = "https://gitlab.com/mango-agents/Mango.jl",
)
