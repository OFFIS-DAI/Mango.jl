module CommunicationSimulationModule

# Communication Sim Interface
abstract type CommunicationSimulation end

struct PackageResult
    reached::Bool
    delay::UInt64    
end

struct CommunicationSimulationResult 
    package_results::Vector{PackageResult}
end

struct MessagePackage
    aid_one::String
    aid_two::String
    sent_date::DateTime
    content::Any
end

function calculate_communication(communication_sim::CommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult 
    throw(ErrorException("Please implement calculate_communication(...)"))
end

# Default Implementation Communication Sim
@with_kw struct SimpleCommunicationSimulation <: CommunicationSimulation
    delay_directed_edge_vector::Dict{Tuple{String, String},Float64} = Dict()
end

function calculate_communication(communication_sim::SimpleCommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult 
    results::Vector{PackageResult} = Vector()
    for message in messages
        key = (message.aid_one, message.aid_two)
        delay = 0
        if haskey(communication_sim.delay_directed_edge_vector, key)
            delay = communication_sim.delay_directed_edge_vector[key]
        end
        push!(results, PackageResult(true, delay))
    end
    return CommunicationSimulationResult(package_results)
end

end