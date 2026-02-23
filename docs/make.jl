
using Documenter, Mango, Test, Logging

logger = Test.TestLogger(min_level=Info);

with_logger(logger) do
    makedocs(
        modules=[Mango],
        format=Documenter.HTML(; assets=["assets/mango_theme_overrides.css"], prettyurls=get(ENV, "CI", nothing) == "true"),
        authors="mango Team",
        sitename="Mango.jl Documentation",
        pages=Any[
            "Home" => "index.md",
            "Getting Started" => "getting_started.md",
            "Tutorials" => [
                "Ping-Pong with TCP"        => "tutorials/ping_pong.md",
                "Ping-Pong in Simulation"   => "tutorials/simulation.md",
                "EV Coordination"           => "tutorials/ev_coordination.md",
            ],
            "Concepts" => "concepts.md",
            "Agent Programming" => [
                "Agents"     => "agent.md",
                "Roles"      => "role.md",
                "Scheduling" => "scheduling.md",
                "Topology"   => "topology.md",
            ],
            "Real-Time Mode" => [
                "Container (TCP / MQTT)" => "container.md",
                "Codecs"                 => "encode_decode.md",
            ],
            "Simulation Mode" => [
                "Simulation" => "simulation.md",
            ],
            "API"    => "api.md",
            "Legals" => "legals.md",
        ],
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
    push_preview=true,
    devbranch="development"
)