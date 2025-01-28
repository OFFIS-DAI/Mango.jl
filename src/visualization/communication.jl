export plot_topology, show_communication_data

using Makie
using GraphMakie.NetworkLayout
using GraphMakie
using Graphs
using Dates

function plot_topology(topology::Topology; write_to::Union{Nothing,String}="topology.svg", ax=nothing, fig=Figure())

    if isnothing(ax)
        ax = Axis(fig[1, 1])
    end

    g = topology.graph
    graphplot!(ax, g, layout=Shell(),
        elabels=["$i" for i in 1:ne(g)],
        arrow_show=true,
        node_size=48,
        node_color=:gray,
        arrow_size=24,
        ilabels=repr.(1:nv(g)),
        ilabels_color=:white)

    hidedecorations!(ax)
    hidespines!(ax)

    if !isnothing(write_to)
        save(write_to, fig)
    end
end

function _to_seconds(date::DateTime, init::DateTime)
    return (date - init).value / 1000
end

function _find_edge(graph::AbstractGraph, sender_id::Int, receiver_id::Int)
    for (i, edge) in enumerate(edges(graph))
        if collect(labels(graph))[src(edge)] == sender_id && collect(labels(graph))[dst(edge)] == receiver_id
            return i, edge
        end
    end
    return -1
end

function show_communication_data(topology::Topology,
    messages::Vector{MessageTransaction},
    initial_time::DateTime=DateTime(0);
    resolution_s::Real=0.1,
    show::Bool=true,
    size=(1200, 800))

    g = topology.graph

    if !is_directed(topology.graph)
        edge_data = [[(e[1], e[2]) => topology.graph[e[1], e[2]] for e in edge_labels(topology.graph)];
            [(e[2], e[1]) => topology.graph[e[1], e[2]] for e in edge_labels(topology.graph)]]
        vertex_data = [l => topology.graph[l] for l in labels(topology.graph)]
        underlying_graph = DiGraph(topology.graph.graph)
        g = MetaGraph(underlying_graph, vertex_data, edge_data)
    end

    fig = Figure(size=size)
    ax = Axis(fig[1, 1])

    min_date = initial_time
    max_date = max([m.arriving_date for m in messages]...)

    delta = _to_seconds(max_date, min_date)
    sg = SliderGrid(fig[2, 1],
        (label="Time", range=0:resolution_s:delta, format="{:.1f}", startvalue=0),
        tellheight=true)

    sliderobservable = sg.sliders[1].value

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
        i_elabels = ["" for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    i_elabels[found[1]] = "$(typeof(message.content))"
                end
            end
        end
        i_elabels
    end

    efull = lift(sliderobservable) do time
        i_efull = ["" for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    i_efull[found[1]] = "$(message.content)"
                end
            end
        end
        i_efull
    end

    arrow_markers = lift(sliderobservable) do time
        markers = [:hline for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    markers[found[1]] = :rtriangle
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

    edge_width = lift(sliderobservable) do time
        ew = [1.0 for _ in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time <= _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    ew[found[1]] = 6
                end
            end
        end
        ew
    end

    p = graphplot!(ax, g, layout=Shell(),
        edge_color=edgecolors,
        elabels=elabels,
        arrow_show=true,
        edge_width=edge_width,
        node_size=48,
        node_color=:gray,
        node_strokewidth=0,
        arrow_size=24,
        arrow_shift=arrow_shifts,
        arrow_marker=arrow_markers,
        ilabels=repr.(1:nv(g)),
        ilabels_color=:white,
        elabels_attr=(word_wrap_width=5,))

    hidedecorations!(ax)
    hidespines!(ax)

    deregister_interaction!(ax, :rectanglezoom)
    register_interaction!(ax, :ndrag, NodeDrag(p))

    function edge_hover_action(state, idx, event, axis)
        if !state
            sliderobservable[] = sliderobservable[]
        end
        p.elabels[][idx] = state ? efull[][idx] : elabels[][idx]
        p.elabels[] = p.elabels[]
    end
    ehover = EdgeHoverHandler(edge_hover_action)
    register_interaction!(ax, :ehover, ehover)

    if show
        wait(display(fig))
    else
        save("communication.svg", fig)
    end
    return fig
end

function show_communication_data(topology::Topology,
    world::World;
    resolution_s::Real=0.1,
    show::Bool=true)
    return show_communication_data(topology, world.recorded_messages, world.initial_time,
        resolution_s=resolution_s, show=show)
end