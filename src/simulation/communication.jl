export CommunicationSimulation, PackageResult, CommunicationSimulationResult, MessagePackage, calculate_communication, 
    SimpleCommunicationSimulation, DelayProviderCommunicationSimulation, create_distribution_based_com_sim

using Dates
using Graphs
using MetaGraphsNext
using Distributions

"""
Interface to implement a communication simulation. 
"""
abstract type CommunicationSimulation end

"""
Package result 
"""
struct PackageResult
    reached::Bool
    delay_s::Real
end

"""
List of package results
"""
struct CommunicationSimulationResult
    package_results::Vector{PackageResult}
end

"""
Struct describing a mesage between two agents.
"""
struct MessagePackage
    sender_id::Union{String,Nothing}
    receiver_id::String
    sent_date::DateTime
    content::Any
end

"""
    calculate_communication(communication_sim::CommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult

Calculate the communication using the specific communication simulation type. the current
simulation time `clock` and the message which shall be sent in this step `messages`. 

Note that the method can be called multiple times with the same MessePackage objects. It is necessary that implementations of this method, will always return
the same result for the (exact!) same message package.
"""
function calculate_communication(communication_sim::CommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult
    throw(ErrorException("Please implement calculate_communication(...)"))
end

"""
Default Implementation Communication Sim.

Implements a default delay which determines the delay of all messages if not specified in 
`delay_s_directed_edge_dict`. The dict can contain a mapping (aid_sender, aid_receiver) -> delay,
such that the delay is specified for every link between agents.
"""
@kwdef struct SimpleCommunicationSimulation <: CommunicationSimulation
    default_delay_s::Real = 0
    delay_s_directed_edge_dict::Dict{Tuple{Union{String,Nothing},String},Real} = Dict()
end

function calculate_communication(communication_sim::SimpleCommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult
    results::Vector{PackageResult} = Vector()
    for message in messages
        key = (message.sender_id, message.receiver_id)
        delay_s = communication_sim.default_delay_s
        if haskey(communication_sim.delay_s_directed_edge_dict, key)
            delay_s = communication_sim.delay_s_directed_edge_dict[key]
        end
        push!(results, PackageResult(true, delay_s))
    end
    return CommunicationSimulationResult(results)
end

"""
Dynamically-based communication delay provider implementation for a communication simulation.

With this implementation you are able to set a default provider function, which return a delay_s on
call, when no other provider are defined. To assign a speicific delay provider for an edge between 
agents, `delay_s_directed_edge_dict` can be used.
"""
@kwdef struct DelayProviderCommunicationSimulation <: CommunicationSimulation
    default_delay_s_provider::Function = () -> 0
    delay_s_directed_edge_dict::Dict{Tuple{Union{String,Nothing},String},Function} = Dict()
    message_cache::Dict{MessagePackage,PackageResult} = Dict()
end

function calculate_communication(communication_sim::DelayProviderCommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult
    results::Vector{PackageResult} = Vector()
    for message in messages
        if haskey(communication_sim.message_cache, message)
            push!(results, communication_sim.message_cache[message])
            continue
        end
        key = (message.sender_id, message.receiver_id)
        delay_s = communication_sim.default_delay_s_provider()
        if haskey(communication_sim.delay_s_directed_edge_dict, key)
            delay_s = communication_sim.delay_s_directed_edge_dict[key]()
        end
        pr = PackageResult(true, delay_s)
        communication_sim.message_cache[message] = pr
        push!(results, pr)
    end
    return CommunicationSimulationResult(results)
end

function create_distribution_based_com_sim(aid_graph::MetaGraph, 
                                        agents::Vector{Agent};
                                        default_delay_per_edge::Real=1, 
                                        base_delay_per_message::Real=20, 
                                        distribution_provider::Function=(delay) -> Poisson(delay),
                                        label_replacer::Function=(label) -> label)::DelayProviderCommunicationSimulation

    distmatrix = fill(0, nv(aid_graph), nv(aid_graph))
    for edge in edges(aid_graph)
        from = src(edge)
        to = dst(edge)
        distmatrix[from, to] = default_delay_per_edge
        distmatrix[to, from] = default_delay_per_edge
    end
    default_distr = distribution_provider(base_delay_per_message)
    provider_com = DelayProviderCommunicationSimulation(default_delay_s_provider=() -> abs(rand(default_distr)) / 1000)
    for agent in agents
        label = aid(agent)

        label = label_replacer(label)
        
        code = code_for(aid_graph, label)
        ds = dijkstra_shortest_paths(aid_graph, code, distmatrix)
        
        for (code_other, distance) in enumerate(ds.dists)
            label_other = label_for(aid_graph, code_other)
            specific_distr = distribution_provider(base_delay_per_message + distance)
            provider_com.delay_s_directed_edge_dict[(aid(agent), label_other)] = () -> abs(rand(specific_distr)) / 1000
            provider_com.delay_s_directed_edge_dict[(label_other, aid(agent))] = provider_com.delay_s_directed_edge_dict[(label, label_other)]
        end
    end
    return provider_com 
end