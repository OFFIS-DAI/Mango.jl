
using Documenter, Mango, Test, Logging

logger = Test.TestLogger(min_level=Info);

with_logger(logger) do
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
            "API"=>"api.md",
            "Legals"=>"legals.md",],
        repo="https://github.com/OFFIS-DAI/Mango.jl",
    )
end

for record in logger.logs
    @info record.message
    # Check if @example blocks did not succeed -> fail then
    if record.level == Warn && occursin("failed to run `@example` block", record.message)
        throw("Some Documentation example did not work, check the logs and fix the error.")
    end
end

deploydocs(
    repo="github.com/OFFIS-DAI/Mango.jl.git",
    push_preview=true
)