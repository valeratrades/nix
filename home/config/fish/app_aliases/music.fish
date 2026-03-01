function pp
	# Usage: `pp 1.25 ~/Music/Appassionata_-_Beethoven/lisitsa.m3u`
	if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $argv[1]
		echo "pp: first argument must be a number" >&2
		return 1
	end
	set -l vol (wpctl get-volume @DEFAULT_AUDIO_SINK@ | string replace -r 'Volume: ' '')
	if test "$vol" -gt 0.5
		read -l -P "Volume is at $(math "round($vol * 100)")%. Continue? [y/N] " confirm
		if not string match -qi 'y' -- $confirm
			return 1
		end
	end
	mpv --no-terminal --no-video --loop-file --loop-playlist --speed=$argv[1] $argv[2]
end
alias pp1="pp 1.0"
