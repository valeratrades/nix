set __fish_config_eww_dir (dirname (status --current-filename))

function eww_open
	#NB: ordering matters, - will determine who overlays who in case of overlap
	for window in (cat $__fish_config_eww_dir/eww_windows.txt)
		eww open $window
	end
end
