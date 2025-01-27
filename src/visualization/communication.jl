export plot, show_communication_data

using GraphMakie.NetworkLayout
using GraphMakie
using Graphs
using Dates

function _to_seconds(date::DateTime, init::DateTime)
    return (date - init).value / 1000
end

function _find_edge(graph::AbstractGraph, sender_id::Int, receiver_id::Int)
    for (i, edge) in enumerate(edges(graph))
        if collect(labels(graph))[src(edge)] == sender_id && collect(labels(graph))[dst(edge)] == receiver_id
            return i, edge, :sender
        elseif collect(labels(graph))[dst(edge)] == sender_id && collect(labels(graph))[src(edge)] == receiver_id
            return i, edge, :receiver
        end
    end
    return -1
end

function show_communication_data(topology::Topology,
    messages::Vector{MessageTransaction},
    initial_time::DateTime=DateTime(0);
    resolution_s::Real=0.1,
    display::Bool=true)

    fig = Figure()
    ax = Axis(fig[1, 1])

    min_date = initial_time
    max_date = max([m.arriving_date for m in messages]...)

    delta = _to_seconds(max_date, min_date)
    sg = SliderGrid(fig[2, 1],
        (label="Time", range=0:resolution_s:delta, format="{:.1f}", startvalue=0),
        tellheight=true)

    sliderobservable = sg.sliders[1].value

    g = topology.graph
    aid_to_node_id = Dict{String,Int}()
    for label in labels(topology.graph)
        node = topology.graph[label]
        for agent in node.agents
            aid_to_node_id[aid(agent)] = label
        end
    end
    edgecolors = lift(sliderobservable) do time
        edgecolors = [:black for i in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id],
                    aid_to_node_id[message.receiver_id])
                if found != -1
                    edgecolors[found[1]] = :red
                end
            end
        end
        edgecolors
    end

    elabels = lift(sliderobservable) do time
        elabels = ["" for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    elabels[found[1]] = "$(typeof(message.content)): $(last("$(message.content)", 5))"
                end
            end
        end
        elabels
    end

    arrow_markers = lift(sliderobservable) do time
        markers = [:hline for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    markers[found[1]] = found[3] == :sender ? :rtriangle : :ltriangle
                end
            end
        end
        markers
    end

    arrow_shifts = lift(sliderobservable) do time
        shifts = [1.0 for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    shifts[found[1]] = 0.8
                end
            end
        end
        shifts
    end

    graphplot!(ax, g, layout=Shell(),
        edge_color=edgecolors,
        elabels=elabels,
        arrow_show=true,
        node_size=48,
        node_color=:gray,
        arrow_size=24,
        arrow_shift=arrow_shifts,
        arrow_marker=arrow_markers,
        ilabels=repr.(1:nv(g)),
        ilabels_color=:white)

    hidedecorations!(ax)
    hidespines!(ax)

    if display
        wait(display(fig))
    end
    return fig
end

function show_communication_data(topology::Topology,
    world::World;
    resolution_s::Real=0.1,
    display::Bool=true)
    return show_communication_data(topology, world.recorded_messages, world.initial_time,
        resolution_s=resolution_s, display=display)
end