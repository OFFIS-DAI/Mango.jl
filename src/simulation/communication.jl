export CommunicationSimulation, PackageResult, CommunicationSimulationResult, MessagePackage, calculate_communication, SimpleCommunicationSimulation

using Dates

"""
Interface to implement a communication simulation. 
"""
abstract type CommunicationSimulation end

"""
Package result 
"""
struct PackageResult
    reached::Bool
    delay_s::UInt64
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
simulation time `clock` and the message which shall be sent in this step `messages`
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

"""
Implementation for SimpleCommunicationSimulation
"""
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
