source (dirname (status --current-filename))/videos.fish
source (dirname (status --current-filename))/server.fish
source (dirname (status --current-filename))/weird.fish
source (dirname (status --current-filename))/document_watch.fish

function beep
	set dir (dirname (status --current-filename))
	cargo -Zscript -q $dir/beep.rs $dir/assets/sound/Notification.mp3 $argv
end
function timer
	cargo -Zscript -q (dirname (status --current-filename))/timer.rs $argv
end

alias q="py $HOME/s/help_scripts/ask_gpt.py -s $argv"
alias f="py $HOME/s/help_scripts/ask_gpt.py -f $argv"

alias toggle_theme="$HOME/s/help_scripts/theme_toggle.sh"

alias choose_port="$HOME/s/help_scripts/choose_port.sh"
