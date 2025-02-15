
function log_exception(e, backtrace=nothing)
    bt = catch_backtrace()
    if !isnothing(backtrace)
        bt = backtrace
    end
    msg = sprint(io -> begin
        println(io, "Exception occurred in thread ", Threads.threadid())
        showerror(io, e)
        println(io)
        Base.show_backtrace(io, bt)
    end)
    @error msg
end

macro spawnlog(expr)
    quote
        Threads.@spawn try
            $(esc(expr))
        catch ex
            log_exception(ex)
            rethrow(ex)
        end
    end
end
