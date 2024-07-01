module CommunicationSimulation

# Communication Sim
abstract type CommunicationSim end

struct PackageResult
    reached::Bool
    delay::UInt64    
end

@with_kw struct CommunicationSimResult 
    package_to_result::Dict{UUID, PackageResult} = Dict()
    state_changed::Bool = false
end

struct MessagePackage
    aid_one::String
    aid_two::String
    sent_date::DateTime
    content::Vector{UInt8}
    package_id::UUID
end

function simulate(communication_sim::CommunicationSim, message_package::MessagePackage) end
function step(communication_sim::CommunicationSim)::CommunicationSimResult end
function package_for(communication_sim::CommunicationSim, id::UUID)::MessagePackage end

struct SimpleCommunicationSim <: CommunicationSim
end


function step(com_sim::SimpleCommunicationSim)::CommunicationSimResult 
    result = CommunicationSimResult()
end
end