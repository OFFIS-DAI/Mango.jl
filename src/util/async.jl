export @asynclog

"""
Can be used as replacement for @async with the only difference
that it will actually print errors thrown by the async tasks instead
of absorbing them. 
"""
macro asynclog(expr)
    quote
        @async try
            $(esc(expr))
        catch ex
            bt = stacktrace(catch_backtrace())
            showerror(stderr, ex, bt)
            rethrow(ex)
        end
    end
end