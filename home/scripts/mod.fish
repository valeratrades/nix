set fish_scripts_pdir (dirname (status --current-filename))
source $fish_scripts_pdir/videos.fish
source $fish_scripts_pdir/server.fish
source $fish_scripts_pdir/weird/mod.fish
source $fish_scripts_pdir/document_watch.fish

function beep
	cargo -Zscript -q $fish_scripts_pdir/beep.rs $fish_scripts_pdir/assets/sound/Notification.mp3 $argv
end
function timer
	cargo -Zscript -q $fish_scripts_pdir/timer.rs $argv
end

alias q="py $fish_scripts_pdir/ask_gpt.py -s $argv"
alias f="py $fish_scripts_pdir/ask_gpt.py -f $argv"

alias theme_toggle="$fish_scripts_pdir/theme_toggle.sh"
alias choose_port="$fish_scripts_pdir/choose_port.sh"
