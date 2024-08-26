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

function get_types(type_curly_expr::Expr)
    type_args = []
    type_args_full = []
    for i in 2:length(type_curly_expr.args)
        type_arg = type_curly_expr.args[i]
        push!(type_args_full, type_arg)
        if typeof(type_arg) == Symbol
            push!(type_args, type_arg)
        else
            push!(type_args, type_arg.args[1])
        end
    end
    return type_args, type_args_full
end

macro with_def(struct_def)
    Base.remove_linenums!(struct_def)

    struct_head = struct_def.args[2]
    struct_name = struct_head
    type_clause = nothing
    type_args = []
    type_args_full = []
    if typeof(struct_name) != Symbol
        struct_name = struct_head.args[1]
        if typeof(struct_name) != Symbol
            struct_head_sub = struct_name
            struct_name = struct_head_sub.args[1]
            if struct_head_sub.head == :curly
                type_clause = struct_head_sub.args[2]
                type_args, type_args_full = get_types(struct_head_sub)
            end
        end
        if struct_head.head == :curly
            type_clause = struct_head.args[2]
            type_args, type_args_full = get_types(struct_head)
        end
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
    args_compl = length(type_args) == 0 ?
                 Symbol(:new) :
                 Expr(:curly, Symbol(:new), type_args...)

    args_names_new = length(struct_field_names) == 0 ?
                     Expr(:call, args_compl) :
                     Expr(:call, args_compl, struct_field_names...)

    call_clause = length(args) == 0 ? Expr(:call, Symbol(struct_name),
        length(args_with_default) == 0 ? Expr(:parameters,) : Expr(:parameters, args_with_default...)
    ) :
                  Expr(:call, Symbol(struct_name),
        length(args_with_default) == 0 ? Expr(:parameters,) : Expr(:parameters, args_with_default...),
        args...
    )
    with_where_clause = length(type_args) == 0 ? call_clause : Expr(:where, call_clause, type_args_full...)

    default_constructor = Expr(:function,
        with_where_clause,
        Expr(:block, args_names_new)
    )

    # Create the new struct definition
    new_struct_def = Expr(
        :struct,
        true,
        struct_head,
        length(struct_fields_without_def) == 0 ? Expr(:block) : Expr(:block, struct_fields_without_def..., default_constructor),
    )

    esc(Expr(:block, new_struct_def))
end
