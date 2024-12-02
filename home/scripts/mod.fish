set pwd (dirname (status --current-filename))
source $pwd/videos.fish
source $pwd/server.fish
source $pwd/weird.fish
source $pwd/document_watch.fish

function beep
	set dir (dirname (status --current-filename))
	cargo -Zscript -q $dir/beep.rs $dir/assets/sound/Notification.mp3 $argv
end
function timer
	cargo -Zscript -q (dirname (status --current-filename))/timer.rs $argv
end

alias q="py $pwd/ask_gpt.py -s $argv"
alias f="py $pwd/ask_gpt.py -f $argv"

alias toggle_theme="$pwd/theme_toggle.sh"

alias choose_port="$pwd/choose_port.sh"
