export CommunicationSimulation, PackageResult, CommunicationSimulationResult, MessagePackage, calculate_communication, SimpleCommunicationSimulation

using Dates

# Communication Sim Interface
abstract type CommunicationSimulation end

struct PackageResult
	reached::Bool
	delay_s::UInt64
end

struct CommunicationSimulationResult
	package_results::Vector{PackageResult}
end

struct MessagePackage
	sender_id::Union{String, Nothing}
	receiver_id::String
	sent_date::DateTime
	content::Any
end

function calculate_communication(communication_sim::CommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult
	throw(ErrorException("Please implement calculate_communication(...)"))
end

# Default Implementation Communication Sim
@kwdef struct SimpleCommunicationSimulation <: CommunicationSimulation
	default_delay_s::Real = 0
	delay_s_directed_edge_vector::Dict{Tuple{Union{String, Nothing}, String}, Real} = Dict()
end

function calculate_communication(communication_sim::SimpleCommunicationSimulation, clock::Clock, messages::Vector{MessagePackage})::CommunicationSimulationResult
	results::Vector{PackageResult} = Vector()
	for message in messages
		key = (message.sender_id, message.receiver_id)
		delay_s = communication_sim.default_delay_s
		if haskey(communication_sim.delay_s_directed_edge_vector, key)
			delay_s = communication_sim.delay_s_directed_edge_vector[key]
		end
		push!(results, PackageResult(true, delay_s))
	end
	return CommunicationSimulationResult(results)
end
