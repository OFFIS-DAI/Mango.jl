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
    pairs = collect(data.timeseries)
    labels = [pair[1] for pair in pairs]
    values = [pair[2] for pair in pairs]
    if data.dedicated_plots
        for (i, agent) in enumerate(labels)
            ax = Axis(fig[i],
                title="$recording over time for $agent",
                xlabel="time (seconds)",
                ylabel=recording,
            )
            lines!(ax, data.time, values[i], color=:black)
        end
    else
        ax = Axis(fig[1,1],
            title="$recording over time for each agent",
            xlabel="time (seconds)",
            ylabel=recording,
        )
        series!(ax, data.time, hcat(values...)', labels=labels, color=color)
        Legend(fig[1, 2], ax)
    end
    if !isnothing(write_to)
        save(write_to, fig)
    end
end

function _create_label(layout, label, y)
    return Label(layout[y, 1, TopLeft()], label,
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

    row_length = 3
    dc = world.data_collections
    dac = world.data_agent_collections
    if size == :auto
        dac_length = sum([record.dedicated_plots ? length(record.timeseries) : 1 for record in values(dac)])
        size = (
            min(max(length(dc), dac_length), 3) * 400,
            600 + ((length(dc)-1) ÷ 3 + (dac_length-1) ÷ 3) * 250 
        )
    end
    main_fig = Figure(size=size)
    all_layout = main_fig[1, 1] = GridLayout()

    _create_label(all_layout, "W", 1)
    for (i, key) in enumerate(keys(dc))
        layout_fig = all_layout[((i - 1) ÷ row_length) + 1, ((i - 1) % row_length) + 1]
        plot_world(world, key, write_to=nothing, fig=layout_fig, color=color, colormap=colormap)
    end

    y_start_agents = (((length(dc) - 1) ÷ row_length) + 2)
    shift = (y_start_agents-1) * row_length

    _create_label(all_layout, "A", y_start_agents)
    for (i, key) in enumerate(keys(dac))
        layout_fig = all_layout[(((i+shift) - 1) ÷ row_length) + 1, (((i+shift) - 1) % row_length) + 1]
        current_dac = dac[key]
        if current_dac.dedicated_plots
            layouts = [all_layout[(((i+shift+j-1) - 1) ÷ row_length) + 1, (((i+shift+j-1) - 1) % row_length) + 1] 
                        for j in 1:length(current_dac.timeseries)]
            plot_agents(world, key, write_to=nothing, fig=layouts, color=colormap)
            shift += length(current_dac.timeseries) - 1
        else
            plot_agents(world, key, write_to=nothing, fig=layout_fig, color=colormap)
        end
    end

    if !isnothing(write_to)
        return save(write_to, main_fig)
    end
end