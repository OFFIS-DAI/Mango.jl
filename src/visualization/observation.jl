export plot_world, plot_agents, plot_recordings

using Makie

function plot_world(world::World, recording::String;
    write_to::Union{Nothing,String}="world_observation.png",
    fig=Figure(),
    color=:black,
    colormap=:default)

    data = data_collection(world, recording)
    ax = Axis(fig,
        title="$recording over time",
        xlabel="time (seconds)",
        ylabel=recording,
    )
    lines!(ax, data.time, data.timeseries, color=color, colormap=colormap)
    if !isnothing(write_to)
        save(write_to, fig)
    end
end

function plot_agents(world::World, recording::String;
    write_to::Union{Nothing,String}="agent_observation.png",
    fig=Figure(),
    color=:viridis)

    data = data_agent_collection(world, recording)
    ax = Axis(fig[1,1],
        title="$recording over time for each agent",
        xlabel="time (seconds)",
        ylabel=recording,
    )
    pairs = collect(data.timeseries)
    labels = [pair[1] for pair in pairs]
    values = [pair[2] for pair in pairs]
    series!(ax, data.time, hcat(values...)', labels=labels, color=color)
    Legend(fig[1, 2], ax)
    if !isnothing(write_to)
        save(write_to, fig)
    end
end

function _create_label(layout, label)
    return Label(layout[1, 1, TopLeft()], label,
        fontsize=26,
        font=:bold,
        padding=(0, 5, 5, 0),
        halign=:left)
end

function plot_recordings(world::World;
    write_to::Union{Nothing,String}="observation.png",
    size=:auto,
    color=:black,
    colormap=:viridis)

    dc = world.data_collections
    dac = world.data_agent_collections
    if size == :auto
        size = (
            min(max(length(dc), length(dac)), 3) * 400,
            600 + ((length(dc)-1) ÷ 3 + (length(dac)-1) ÷ 3) * 250 
        )
    end
    main_fig = Figure(size=size)
    world_layout = main_fig[1, 1] = GridLayout()
    agent_layout = main_fig[2, 1] = GridLayout()

    for (i, key) in enumerate(keys(dc))
        layout_fig = world_layout[((i - 1) ÷ 3) + 1, ((i - 1) % 3) + 1]
        plot_world(world, key, write_to=nothing, fig=layout_fig, color=color, colormap=colormap)
    end
    _create_label(world_layout, "W")

    for (i, key) in enumerate(keys(dac))
        layout_fig = agent_layout[((i - 1) ÷ 3) + 1, ((i - 1) % 3) + 1]
        plot_agents(world, key, write_to=nothing, fig=layout_fig, color=colormap)
    end
    _create_label(agent_layout, "A")

    if !isnothing(write_to)
        return save(write_to, main_fig)
    end
end