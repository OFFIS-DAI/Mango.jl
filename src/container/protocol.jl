module ProtocolCore
export Protocol, send, start

abstract type Protocol{T} end

function send(protocol::Protocol{T}, destination::T, message::Any) where T end

function init(protocol::Protocol{T}, stop_check::Function, data_handler::Function) where T end

include("./tcp.jl")

end
