set pdir (dirname (status --current-filename))
source $pdir/videos.fish
source $pdir/server.fish
source $pdir/weird.fish
source $pdir/document_watch.fish

function beep
	cargo -Zscript -q $pdir/beep.rs $pdir/assets/sound/Notification.mp3 $argv
end
function timer
	cargo -Zscript -q $pdir/timer.rs $argv
end

alias q="py $pdir/ask_gpt.py -s $argv"
alias f="py $pdir/ask_gpt.py -f $argv"

alias theme_toggle="$pdir/theme_toggle.sh"
alias choose_port="$pdir/choose_port.sh"
