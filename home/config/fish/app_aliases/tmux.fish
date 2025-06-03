#alias tmux="TERM='alacritty-direct' tmux"
alias ta="tmux attach -t"
alias tl="tmux ls"
alias tks="tmux kill-server"

function tk --description "Kill tmux session + direnv deny its root"
	if test (count $argv) != 1
		echo "Usage: tk <session_name>"
		returnt1
	end
	set requested_session $argv[1]
	set session_path (tmux display-message -p -t "$requested_session" "#{session_path}")
	tmux kill-session -t "$requested_session"
	direnv deny "$session_path" >/dev/null 2>&1
end

function tmux_new_session_base
	if test -n "$TMUX"
		echo "Already in a tmux session."
		return 1
	end
	if test -n "$argv[2]"
		cd $argv[2]; or return 1
	end
	set -l SESSION_NAME (basename (pwd))
	if test -n "$argv[1]"
		set SESSION_NAME $argv[1]
	end
	set SESSION_NAME (echo "$SESSION_NAME" | sed 's/\./_/g')
	# add -tmp if parent directory is exactly "tmp" and session name doesn't already start with it
	set -l PARENT_DIR (basename (dirname (pwd)))
	if test "$PARENT_DIR" = "tmp"
		if not string match -q 'tmp-*' -- "$SESSION_NAME"
			set SESSION_NAME "tmp-$SESSION_NAME"
		end
	end
	if tmux has-session -t "$SESSION_NAME" 2>/dev/null
		echo "Session $SESSION_NAME already exists."
		return 1
	end

	# Source window
	tmux new-session -d -s "$SESSION_NAME" -n "source"
	tmux send-keys -t "$SESSION_NAME:source.0" 'nvim .' Enter

	# Build window
	tmux new-window -t "$SESSION_NAME" -n "build"
	tmux send-keys -t "$SESSION_NAME:build.0" 'cs .' Enter
	tmux split-window -h -t "$SESSION_NAME:build"
	tmux send-keys -t "$SESSION_NAME:build.1" 'cs .' Enter
	tmux split-window -v -t "$SESSION_NAME:build.1"
	tmux send-keys -t "$SESSION_NAME:build.2" 'cs .; clear' Enter
	tmux resize-pane -t "$SESSION_NAME:build.2" -D 30
	tmux select-pane -t "$SESSION_NAME:build.0"

	# Tmp window
	tmux new-window -t "$SESSION_NAME" -n "tmp"
	tmux send-keys -t "$SESSION_NAME:tmp.0" 'cd tmp; clear' Enter
	tmux split-window -h -t "$SESSION_NAME:tmp"
	tmux send-keys -t "$SESSION_NAME:tmp.1" 'cd tmp; clear' Enter
	tmux split-window -v -t "$SESSION_NAME:tmp.1"
	tmux send-keys -t "$SESSION_NAME:tmp.2" 'cd tmp; clear' Enter
	tmux send-keys -t "$SESSION_NAME:tmp.0" 'nvim .' Enter
	tmux select-pane -t "$SESSION_NAME:tmp.0"

	# `window` window
	tmux new-window -t "$SESSION_NAME" -n "window"
	tmux split-window -h -t "$SESSION_NAME:window"
	tmux split-window -v -t "$SESSION_NAME:window.0"
	tmux select-pane -t "$SESSION_NAME:window.0"

	# Ref window
	#// Moved ref to bottom, as I often end up having more than one of these
	#TODO: add a small bottom pane under ref for pulls and test runs
	tmux new-window -t "$SESSION_NAME" -n "r:" # naming convention is "r:<reference-name>"

	echo $SESSION_NAME
	return 0
end

function tn
	#! Github issues init
	set -l session_name_or_err (tmux_new_session_base $argv)
	if test $status = 1
		echo $session_name_or_err
		return 1
	end
	set -l session_name $session_name_or_err

	set -l assume_project_name (basename (pwd))
	if test -n "$argv[1]"
		set assume_project_name $argv[1]
	end

	log_dir="$XDG_STATE_HOME/$assume_project_name/"

	#TODO!: make it use `script` to preserve coloring
	#tmux send-keys -t "$session_name:build.2" 'echo """$(gil)\n$(gifm)\n$(gifa)""" | less' Enter # all issues
	tmux send-keys -t "$session_name:build.2" "nvim \"$log_dir/.log\"" Enter

	# `window`: cd
	tmux send-keys -t "$SESSION_NAME:window.0" "cd ~/.$log_dir && nvim '+AnsiEsc' window.toml" Enter
	tmux send-keys -t "$SESSION_NAME:window.1" "cd ~/.$log_dir && nvim .log..window" Enter
	tmux send-keys -t "$SESSION_NAME:window.1" "cd ~/.$log_dir && window .log" Enter

	tmux attach-session -t "$session_name:source.0"
end
