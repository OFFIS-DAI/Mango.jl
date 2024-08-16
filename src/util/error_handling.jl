
macro spawnlog(expr)
	quote
		Threads.@spawn try
			$(esc(expr))
		catch ex
			bt = stacktrace(catch_backtrace())
			showerror(stderr, ex, bt)
			rethrow(ex)
		end
	end
end
