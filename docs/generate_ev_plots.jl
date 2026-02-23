"""
Standalone script that runs the EV coordination simulation from the tutorial
and saves result plots to docs/src/assets/tutorials/.

Run from the repository root:
    julia --project=. docs/generate_ev_plots.jl
"""

using Mango, Dates, CairoMakie

# ── Message types ─────────────────────────────────────────────────────────────

struct NetPowerReport
    sender_aid::String
    net_power_kw::Float64
    position::Position2D
end

struct EVAssignment
    target::Position2D
    action::Symbol
    power_kw::Float64
end

# ── Household ─────────────────────────────────────────────────────────────────

@agent struct HouseholdAgent
    pv_peak_kw::Float64
    load_kw::Float64
    grid_import_kwh::Float64
    grid_export_kwh::Float64
    self_consumed_kwh::Float64
    coordinator::AgentAddress
end

function pv_output_kw(agent::HouseholdAgent, t::DateTime)
    h = Dates.hour(t) + Dates.minute(t) / 60.0
    return max(0.0, agent.pv_peak_kw * sin(π * (h - 6.0) / 12.0))
end

import Mango.on_step

function on_step(agent::HouseholdAgent, env::Environment, clock::Clock, step_size_s::Real)
    step_h = step_size_s / 3600.0
    pv     = pv_output_kw(agent, clock.simulation_time)
    net    = pv - agent.load_kw
    if net >= 0.0
        agent.self_consumed_kwh += agent.load_kw * step_h
        agent.grid_export_kwh   += net * step_h
    else
        agent.self_consumed_kwh += pv * step_h
        agent.grid_import_kwh   += (-net) * step_h
    end
    pos = location(env.space, agent)
    send_message(agent, NetPowerReport(aid(agent), net, pos), agent.coordinator)
end

# ── EV ────────────────────────────────────────────────────────────────────────

@agent struct EVAgent
    capacity_kwh::Float64
    soc_kwh::Float64
    max_power_kw::Float64
    speed::Float64
    target::Union{Position2D, Nothing}
    action::Symbol
    assigned_power_kw::Float64
end

function on_step(agent::EVAgent, env::Environment, clock::Clock, step_size_s::Real)
    isnothing(agent.target) && return
    step_h  = step_size_s / 3600.0
    current = location(env.space, agent)
    dx      = agent.target.x - current.x
    dy      = agent.target.y - current.y
    dist    = sqrt(dx^2 + dy^2)
    max_travel = agent.speed * step_h
    if dist <= max_travel
        move(env.space, agent, agent.target)
        energy_kwh = agent.assigned_power_kw * step_h
        if agent.action == :charge
            agent.soc_kwh = min(agent.capacity_kwh, agent.soc_kwh + energy_kwh)
        elseif agent.action == :discharge
            agent.soc_kwh = max(0.0, agent.soc_kwh - energy_kwh)
        end
    else
        ratio = max_travel / dist
        move(env.space, agent,
            Position2D(current.x + dx * ratio, current.y + dy * ratio))
    end
end

import Mango.handle_message

function handle_message(agent::EVAgent, msg::EVAssignment, ::AbstractDict)
    agent.target            = msg.target
    agent.action            = msg.action
    agent.assigned_power_kw = msg.power_kw
end

# ── Coordinator ───────────────────────────────────────────────────────────────

@agent struct CoordinatorAgent
    powers::Dict{String, Float64}
    positions::Dict{String, Position2D}
    ev_addresses::Vector{AgentAddress}
end

function handle_message(agent::CoordinatorAgent, msg::NetPowerReport, ::AbstractDict)
    agent.powers[msg.sender_aid]    = msg.net_power_kw
    agent.positions[msg.sender_aid] = msg.position
end

function on_step(agent::CoordinatorAgent, env::Environment, clock::Clock, step_size_s::Real)
    isempty(agent.powers) && return
    surpluses = sort([(k, v) for (k, v) in agent.powers if v  >  0.3], by = x -> -x[2])
    deficits  = sort([(k, v) for (k, v) in agent.powers if v < -0.3], by = x ->  x[2])
    n = length(agent.ev_addresses)
    n == 0 && return
    ev_idx = 1
    for (haid, power) in surpluses
        ev_idx > n && break
        send_message(agent,
            EVAssignment(agent.positions[haid], :charge, min(power, 3.3)),
            agent.ev_addresses[ev_idx])
        ev_idx += 1
    end
    for (haid, power) in deficits
        ev_idx > n && break
        send_message(agent,
            EVAssignment(agent.positions[haid], :discharge, min(-power, 3.3)),
            agent.ev_addresses[ev_idx])
        ev_idx += 1
    end
end

# ── Simulation ────────────────────────────────────────────────────────────────

world = create_world(
    DateTime(2025, 6, 21),
    communication_sim = SimpleCommunicationSimulation(default_delay_s=0),
    space             = Area2D(width=10.0, height=10.0),
)

coord = register(world, CoordinatorAgent(Dict{String,Float64}(), Dict{String,Position2D}(), AgentAddress[]))

h1 = register(world, HouseholdAgent(6.0, 2.0, 0.0, 0.0, 0.0, address(coord)))
h2 = register(world, HouseholdAgent(4.0, 1.5, 0.0, 0.0, 0.0, address(coord)))
h3 = register(world, HouseholdAgent(7.0, 2.5, 0.0, 0.0, 0.0, address(coord)))
h4 = register(world, HouseholdAgent(5.0, 1.0, 0.0, 0.0, 0.0, address(coord)))
h5 = register(world, HouseholdAgent(3.0, 2.0, 0.0, 0.0, 0.0, address(coord)))

ev1 = register(world, EVAgent(40.0, 20.0, 3.3, 3.0, nothing, :idle, 0.0))
ev2 = register(world, EVAgent(40.0, 15.0, 3.3, 3.0, nothing, :idle, 0.0))
ev3 = register(world, EVAgent(40.0, 10.0, 3.3, 3.0, nothing, :idle, 0.0))

push!(coord.ev_addresses, address(ev1), address(ev2), address(ev3))

household_positions = [
    (h1, Position2D(1.0, 3.0)),
    (h2, Position2D(1.0, 8.0)),
    (h3, Position2D(5.0, 2.0)),
    (h4, Position2D(7.0, 8.0)),
    (h5, Position2D(9.0, 5.0)),
]

activate(world) do
    for (h, pos) in household_positions
        move(world.env.space, h, pos)
    end

    record_agent!(a -> a isa EVAgent ? a.soc_kwh           : nothing, world, "soc")
    record_agent!(a -> a isa HouseholdAgent ? a.grid_import_kwh   : nothing, world, "import")
    record_agent!(a -> a isa HouseholdAgent ? a.self_consumed_kwh : nothing, world, "self_consumed")
    record_agent!(a -> a isa HouseholdAgent ? a.grid_export_kwh   : nothing, world, "export")
    record_position!(world, filter = a -> a isa EVAgent)

    for _ in 1:24
        step_simulation(world, 3600.0)
    end
end

# ── Extract data ──────────────────────────────────────────────────────────────

soc_data = data_agent_collection(world, "soc")
imp_data = data_agent_collection(world, "import")
sc_data  = data_agent_collection(world, "self_consumed")
ex_data  = data_agent_collection(world, "export")
pos_data = position_history(world)

hours = 0:24                  # time axis (0 = midnight, 24 = next midnight)

ev_colors  = [:royalblue, :crimson, :darkorange]
h_colors   = [:teal, :purple, :sienna, :olivedrab, :steelblue]
ev_agents  = [ev1, ev2, ev3]
ev_labels  = ["EV1", "EV2", "EV3"]
h_agents   = [h1, h2, h3, h4, h5]
h_labels_long = ["H1 (6 kW PV)", "H2 (4 kW PV)", "H3 (7 kW PV)", "H4 (5 kW PV)", "H5 (3 kW PV)"]

# ── Figure 1: SOC + net power ──────────────────────────────────────────────────

fig1 = Figure(size=(1100, 440), fontsize=13)

# ── Panel A: EV state of charge ──
axA = Axis(fig1[1, 1];
    title       = "EV Battery State of Charge",
    xlabel      = "Hour of day",
    ylabel      = "SoC (kWh)",
    xticks      = 0:4:24,
    yticks      = 0:10:40,
)

# Shade the solar window (06:00–18:00)
vspan!(axA, 6, 18; color=(:gold, 0.12))
text!(axA, 12, 38.5; text="solar window", fontsize=11,
      align=(:center, :center), color=(:goldenrod, 0.85))

hlines!(axA, [40]; color=(:gray, 0.4), linestyle=:dash, linewidth=1)   # capacity
text!(axA, 0.5, 40.8; text="capacity", fontsize=10, color=:gray)

for (ev, col, lbl) in zip(ev_agents, ev_colors, ev_labels)
    soc = soc_data.timeseries[aid(ev)]
    lines!(axA, hours, soc; color=col, linewidth=2.5, label=lbl)
    scatter!(axA, [0], [soc[1]]; color=col, markersize=7)
    scatter!(axA, [24], [soc[end]]; color=col, markersize=7)
end

axislegend(axA; position=:lt, framevisible=true)
xlims!(axA, 0, 24)
ylims!(axA, 0, 43)

# ── Panel B: Household net power ──
axB = Axis(fig1[1, 2];
    title   = "Household Net Power (PV − Load)",
    xlabel  = "Hour of day",
    ylabel  = "Net power (kW)",
    xticks  = 0:4:24,
)

hlines!(axB, [0]; color=:black, linewidth=0.8)
vspan!(axB, 6, 18; color=(:gold, 0.12))

# Recompute net power from cumulative data (per-step differences)
for (h, col, lbl) in zip(h_agents, h_colors, h_labels_long)
    imp  = imp_data.timeseries[aid(h)]
    ex   = ex_data.timeseries[aid(h)]
    # net[t] = surplus exported − deficit imported (positive = surplus)
    net  = Float64[]
    for t in eachindex(imp)[2:end]
        push!(net, (ex[t] - ex[t-1]) - (imp[t] - imp[t-1]))
    end
    lines!(axB, 1:24, net; color=col, linewidth=2.0, label=lbl)
end

axislegend(axB; position=:lt, framevisible=true)
xlims!(axB, 0, 24)

Label(fig1[0, :]; text="EV Coordination Simulation — 24-Hour Overview",
      fontsize=15, font=:bold)

save(joinpath(@__DIR__, "src/assets/tutorials/ev_soc_netpower.png"), fig1; px_per_unit=2)
@info "Saved ev_soc_netpower.png"

# ── Figure 2: 2D trajectory map ───────────────────────────────────────────────

fig2 = Figure(size=(540, 540), fontsize=13)

axT = Axis(fig2[1, 1];
    title   = "EV Trajectories over 24 Hours",
    xlabel  = "x (grid units)",
    ylabel  = "y (grid units)",
    aspect  = DataAspect(),
    xticks  = 0:2:10,
    yticks  = 0:2:10,
)

# Draw the 10×10 grid lightly
for x in 0:2:10
    vlines!(axT, x; color=(:lightgray, 0.5), linewidth=0.6)
end
for y in 0:2:10
    hlines!(axT, y; color=(:lightgray, 0.5), linewidth=0.6)
end

# Household locations
h_labels = ["H1", "H2", "H3", "H4", "H5"]
for (label, (_, pos)) in zip(h_labels, household_positions)
    scatter!(axT, [pos.x], [pos.y];
        color=:black, markersize=22, marker=:rect, strokewidth=0)
    scatter!(axT, [pos.x], [pos.y];
        color=:white, markersize=12, marker=:rect, strokewidth=0)
    text!(axT, pos.x, pos.y + 0.6;
        text=label, fontsize=10, align=(:center, :center), font=:bold)
end

# Dummy entry for legend
scatter!(axT, [NaN], [NaN];
    color=:black, markersize=14, marker=:rect, label="Household")

# EV trajectories
for (ev, col, lbl) in zip(ev_agents, ev_colors, ev_labels)
    track = pos_data.timeseries[aid(ev)]
    xs = [p.x for p in track]
    ys = [p.y for p in track]
    lines!(axT, xs, ys; color=(col, 0.55), linewidth=1.6)
    # Hour markers every 6 h
    for h_idx in 1:1:24
        if h_idx <= length(xs)
            scatter!(axT, [xs[h_idx]], [ys[h_idx]];
                color=col, markersize=6, marker=:circle)
        end
    end
    # Start (open circle) and end (star)
    scatter!(axT, [xs[1]], [ys[1]];
        color=col, markersize=10, marker=:circle, strokecolor=col,
        strokewidth=2, label=lbl)
    scatter!(axT, [xs[end]], [ys[end]];
        color=col, markersize=12, marker=:star5)
end

axislegend(axT; position=:lb, framevisible=true)
limits!(axT, -0.5, 10.5, -0.5, 10.5)

Label(fig2[0, 1]; text="EV Movement in the 10×10 Grid\n(circle = start, star = end after 24 h, dots at 6, 12, 18 h)",
      fontsize=12)

save(joinpath(@__DIR__, "src/assets/tutorials/ev_trajectories.png"), fig2; px_per_unit=2)
@info "Saved ev_trajectories.png"

# ── Console summary ───────────────────────────────────────────────────────────

println("\n=== EV state of charge (start → end) ===")
for ev in ev_agents
    soc = soc_data.timeseries[aid(ev)]
    println("  $(aid(ev)): $(round(soc[1], digits=1)) → $(round(soc[end], digits=1)) kWh")
end

println("\n=== Household self-consumption rate ===")
for h in h_agents
    imp = last(imp_data.timeseries[aid(h)])
    sc  = last(sc_data.timeseries[aid(h)])
    den = sc + imp
    scr = den > 0 ? round(100 * sc / den, digits=1) : 100.0
    println("  $(aid(h)): self-consumption $(scr)%  grid import $(round(imp, digits=2)) kWh")
end
