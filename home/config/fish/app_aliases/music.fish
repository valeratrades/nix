function pp
	# Usage: `pp 1.25 ~/Music/Appassionata_-_Beethoven/lisitsa.m3u`
	if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $argv[1]
		echo "pp: first argument must be a number" >&2
		return 1
	end
	mpv --no-terminal --no-video --loop-file --loop-playlist --speed=$argv[1] $argv[2]
end
alias pp1="pp 1.0"
