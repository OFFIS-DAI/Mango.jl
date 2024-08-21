export @with_def

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

macro with_def(struct_def)
    Base.remove_linenums!(struct_def)

    struct_head = struct_def.args[2]
    struct_name = struct_head
    if typeof(struct_name) != Symbol
        struct_name = struct_head.args[1]
    end

    struct_fields = struct_def.args[3].args
    new_struct_field = []
    new_struct_field_default = []
    struct_field_names = []
    struct_fields_without_def = []
    for field in struct_fields
        # has default
        if field.head == :(=)
            push!(new_struct_field_default, (field.args[1], field.args[2]))
            push!(struct_field_names, field.args[1].args[1])
            push!(struct_fields_without_def, field.args[1])
        else
            push!(new_struct_field, field)
            push!(struct_field_names, field.args[1])
            push!(struct_fields_without_def, field)
        end
    end

    args_with_default = [
        Expr(:kw,
            field,
            field_default)
        for (field, field_default) in new_struct_field_default
    ]
    args = new_struct_field

    default_constructor = Expr(:function,
        length(args) == 0 ? Expr(:call, Symbol(struct_name),
            length(args_with_default) == 0 ? Expr(:parameters,) : Expr(:parameters, args_with_default...)
        ) :
        Expr(:call, Symbol(struct_name),
            length(args_with_default) == 0 ? Expr(:parameters,) : Expr(:parameters, args_with_default...),
            args...
        ),
        Expr(:block, length(struct_field_names) == 0 ?
                     Expr(:call, Symbol(:new)) :
                     Expr(:call, Symbol(:new), struct_field_names...)
        ))

    # Create the new struct definition
    new_struct_def = Expr(
        :struct,
        true,
        struct_head,
        length(struct_fields_without_def) == 0 ? Expr(:block) : Expr(:block, struct_fields_without_def..., default_constructor),
    )

    esc(Expr(:block, new_struct_def))
end