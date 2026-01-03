function eww_open
	#NB: ordering matters, - will determine who overlays who in case of overlap
	for window in (cat (dirname (status filename))/eww_windows.txt)
		eww open $window
	end
end
