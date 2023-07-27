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
    # strict = true,
    # clean = true,
    # checkdocs = :exports,
)

# Some setup is needed for documentation deployment, see “Hosting Documentation” and
# deploydocs() in the Documenter manual for more information.
# deploydocs(
#    repo="github.com/mango/Mango.jl.git",
#    push_preview=true
#) 
