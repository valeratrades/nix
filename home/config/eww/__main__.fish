function eww_open
	#NB: ordering matters, - will determine who overlays who in case of overlap
	eww open bar && eww open btc_line_lower && eww open btc_line_upper && eww open claude_sessions && eww open todo_blocker
end
