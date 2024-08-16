using ConcurrentCollections

import Base.length
using Dates

function count_nodes(queue::ConcurrentQueue{T})::Real where {T}
    next = queue.head.next
    count = 0
    while !isnothing(next)
        next = next.next
        count += 1
    end
    return count
end

function add_seconds(date_time::DateTime, inc_s::Real)::DateTime
    return date_time + Millisecond(trunc(Int, inc_s * 1000))
end

function length(queue::ConcurrentQueue{T})::Real where {T}
    return count_nodes(queue)
end

function find_tuple(tuples::Vector, index::Int, value::Any)::Union{Tuple,Nothing}
    for tuple in tuples
        if tuple[index] == value
            return tuple
        end
    end
    return nothing
end
