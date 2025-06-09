
using Mango
using Makie
using GraphMakie.NetworkLayout
using GraphMakie
using Graphs
using Dates
using MetaGraphsNext

function Mango.plot_node_topology(topology::Topology; write_to::Union{Nothing,String}="topology.svg", ax=nothing, fig=Figure())

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

function combine_simple_graphs(graphs::Vector{<:MetaGraph})
    # Count total vertices
    total_vertices = sum(nv(g) for g in graphs)
    combined = SimpleGraph(total_vertices)

    offset = 0
    for g in graphs
        for e in edges(g)
            s = src(e) + offset
            d = dst(e) + offset
            add_edge!(combined, s, d)
        end
        offset += nv(g)
    end
    return combined
end

function combine_meta_graphs(graphs::Vector{<:MetaGraph})
    vertices_description::Vector{Pair{String,Agent}} = []
    edges_description::Vector{Pair{Tuple{String,String},State}} = []
    offset = 0
    for graph in graphs
        vertices_description = [vertices_description; ["$(label_for(graph, i))-$offset" => graph[label_for(graph, i)] for i in vertices(graph)]]
        edges_description = [edges_description; [("$(label_for(graph, src(e)))-$offset", "$(label_for(graph, dst(e)))-$offset") => NORMAL for e in edges(graph)]]
        offset += 1
    end

    return MetaGraph(combine_simple_graphs(graphs), vertices_description, edges_description)
end

function Mango.plot_multi_agent_topology(topologies::Vector{Topology}; write_to::Union{Nothing,String}="multi_topology.svg")
    graphs = [topology_to_aid_graph(top) for top in topologies]
    g = combine_meta_graphs(graphs)
    for top in topologies
        for (connected_type, connected_topology) in top.connections
            for (type, connector) in top.connectors 
                if type == connected_type
                    for (other_type, other_connector) in connected_topology.connectors
                        if other_type == type
                            for i in 0:(length(topologies)-1)
                                offset_i = i
                                for j in 0:(length(topologies)-1)
                                    offset_j = j
                                    aid_f = "$(connector.aid)-$offset_i"
                                    aid_s = "$(other_connector.aid)-$offset_j" 
                                    if aid_f != aid_s
                                        g[aid_f, aid_s] = EXT_CONNECTION
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    fig=Figure()
    ax = Axis(fig[1, 1])
    
    graphplot!(ax, g, layout=Stress(),
        elabels=["" for e in edges(g)],
        node_size=18,
        node_color=:gray,
        ilabels=[name(g[label_for(g,i)]) for i in 1:nv(g)],
        ilabels_color=:white,
        ilabels_fontsize=5)

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

@agent struct VisuProxyAgent
    proxy_aid::String
end

function Mango.aid(agent::VisuProxyAgent)
    return agent.proxy_aid
end

function _create_node_in_for_maybe(g, aid_to_node_id, aid) 
    if !haskey(aid_to_node_id, aid)
        next_id = length(labels(g)) == 0 ? 1 : maximum(collect(labels(g))) + 1

        g[next_id] = Node(id=next_id, agents=[VisuProxyAgent(aid)])
        aid_to_node_id[aid] = next_id
        return next_id
    end
    return aid_to_node_id[aid]
end

function _create_aid_based_data(g, nid, aid_to_x, default)
    label = label_for(g, nid)
    agents = g[label].agents
    if length(agents) > 0
        c_aid = aid(agents[1])
        return get(aid_to_x, c_aid, default)
    end
    return "$label"
end

function Mango.show_communication_data(messages::Vector{MessageTransaction},
    initial_time::DateTime=DateTime(0);
    resolution_s::Real=0.1,
    show::Bool=true,
    size=(1200, 800),
    based_on::Union{Nothing,MetaGraph,Topology}=nothing,
    layout=Spring(C=4),
    aid_to_name::Dict{String,String}=nothing,
    aid_to_color::Dict{String,Symbol}=nothing)

    g = based_on
    if based_on isa Topology
        g = g.graph
    end

    if isnothing(based_on)
        g = MetaGraph(
            DiGraph();
            label_type=Int,
            vertex_data_type=Node,
            edge_data_type=State,
        )
    else
        if !is_directed(g)
            edge_data = [[(e[1], e[2]) => g[e[1], e[2]] for e in edge_labels(g)];
                [(e[2], e[1]) => g[e[1], e[2]] for e in edge_labels(g)]]
            vertex_data = [l => g[l] for l in labels(g)]
            underlying_graph = DiGraph(g.graph)
            g = MetaGraph(underlying_graph, vertex_data, edge_data)
        end
    end

    aid_to_node_id = Dict{String,Int}()
    for label in labels(g)
        node = g[label]
        for agent in node.agents
            aid_to_node_id[aid(agent)] = label
        end
    end

    for message in messages
        old_len = length(g)
        first_node_label = _create_node_in_for_maybe(g, aid_to_node_id, message.sender_id)
        second_node_label = _create_node_in_for_maybe(g, aid_to_node_id, message.receiver_id)

        if old_len != length(g)
            # edge did not exist before
            g[first_node_label, second_node_label] = UNKNOWN
        else
            # edge may exist
            first_node = code_for(g, first_node_label)
            second_node = code_for(g, second_node_label)
            if !has_edge(g, first_node, second_node)
                g[first_node_label, second_node_label] = UNKNOWN
            end
        end
    end

    fig = Figure(size=size)
    ax = Axis(fig[1, 1])

    min_date = initial_time
    max_date = max([m.arriving_date for m in messages]...)

    delta = _to_seconds(max_date, min_date) + resolution_s
    sg = SliderGrid(fig[2, 1],
        (label="Time", range=0:resolution_s:delta, format="{:.2f}", startvalue=0),
        tellheight=true)

    sliderobservable = sg.sliders[1].value

    edgecolors = lift(sliderobservable) do time
        edgecolors = [:black for i in 1:ne(g)]
        for message in messages
            if time >= _to_seconds(message.sent_date, min_date) &&
               time < _to_seconds(message.arriving_date, min_date)

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
               time < _to_seconds(message.arriving_date, min_date)

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
               time < _to_seconds(message.arriving_date, min_date)

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
               time < _to_seconds(message.arriving_date, min_date)

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
               time < _to_seconds(message.arriving_date, min_date)

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
               time < _to_seconds(message.arriving_date, min_date)

                found = _find_edge(g, aid_to_node_id[message.sender_id], aid_to_node_id[message.receiver_id])
                if found != -1
                    ew[found[1]] = 6
                end
            end
        end
        ew
    end

    ilabels = [_create_aid_based_data(g, i, aid_to_name, "unknown") for i in 1:nv(g)]
    node_colors = [_create_aid_based_data(g, i, aid_to_color, :gray) for i in 1:nv(g)]

    p = graphplot!(ax, g, layout=layout,
        edge_color=edgecolors,
        elabels=elabels,
        arrow_show=true,
        edge_width=edge_width,
        node_size=48,
        node_color=node_colors,
        node_strokewidth=0,
        arrow_size=24,
        arrow_shift=arrow_shifts,
        arrow_marker=arrow_markers,
        ilabels=ilabels,
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
        return display(fig)
    else
        save("communication.svg", fig)
    end
    return fig
end

function Mango.show_communication_data(world::World;
    resolution_s::Real=0.1,
    show::Bool=true,
    based_on::Union{Nothing,MetaGraph,Topology}=nothing)

    aid_to_name = Dict(aid(agent) => name(agent) for agent in agents(world))
    aid_to_color = Dict(aid(agent) => color(agent) for agent in agents(world))
    return show_communication_data(world.recorded_messages, 
                world.clock.initial_time,
                resolution_s=resolution_s,
                show=show, 
                based_on=based_on, 
                aid_to_name=aid_to_name,
                aid_to_color=aid_to_color)
end