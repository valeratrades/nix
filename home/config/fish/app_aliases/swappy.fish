function scrn
	# Opens the specified screenshot for editing
	# Ex:
	# scrn ~/Images/Trading/PatternScreenshots/2021-07-01_15-00-00.png
	# scrn
	
	if test (count $argv) -eq 1
		set path $argv[1]
	else
		set path (ls -t ~/tmp/Screenshots | head -n 1)
	end

	swappy -f $path -o $path
end
