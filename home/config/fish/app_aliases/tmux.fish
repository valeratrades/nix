#alias tmux="TERM='alacritty-direct' tmux"
alias ta="tmux attach -t"
complete -c ta -w tmux
alias tl="tmux ls"
complete -c tl -w tmux
alias tks="tmux kill-server"
complete -c tks -w tmux

function tkc --description "Kill the current tmux session"
	if test -z "$TMUX"
		echo "Not in a tmux session."
		return 1
	end
	tmux kill-session -t (tmux display-message -p '#{session_name}')
end

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
	argparse 'a/allow' 'm/math' 'd/detach' -- $argv
	or return 1

	set -l cs_cmd 'cs'
	if set -q _flag_a
		set cs_cmd 'cs -a'
	end
	if set -q _flag_d
		set cs_cmd "$cs_cmd -d"
	end
	set -l detach (set -q _flag_d; and echo 1; or echo 0)
	set -l math_workspace (set -q _flag_m; and echo 1; or echo 0)
	set -l args $argv

	# only nesting is refused; building a detached session from inside tmux is fine
	if test -n "$TMUX"; and test $detach = 0
		echo "Already in a tmux session."
		return 1
	end
	if test -n "$args[2]"
		cd $args[2]; or return 1
	end
	set -l SESSION_NAME (basename (pwd))
	if test -n "$args[1]"
		set SESSION_NAME $args[1]
	end
	set SESSION_NAME (echo "$SESSION_NAME" | sed 's/\./_/g')
	# add tmp- prefix if any ancestor directory is named "tmp" and session name doesn't already start with it
	if not string match -q 'tmp-*' -- "$SESSION_NAME"
		set -l current_path (pwd)
		while test "$current_path" != "/"
			if test (basename "$current_path") = "tmp"
				set SESSION_NAME "tmp-$SESSION_NAME"
				break
			end
			set current_path (dirname "$current_path")
		end
	end
	if tmux has-session -t "=$SESSION_NAME" 2>/dev/null; or tmux has-session -t "=*$SESSION_NAME" 2>/dev/null
		echo "Session $SESSION_NAME already exists."
		return 1
	end

	# Source window
	tmux new-session -d -s "$SESSION_NAME" -n "source"
	if test $math_workspace = 1
		tmux send-keys -t "$SESSION_NAME:source.0" 'typst_workspace' Enter
	else
		tmux send-keys -t "$SESSION_NAME:source.0" 'nvim .' Enter
	end

	# Build window
	tmux new-window -t "$SESSION_NAME" -n "build"
	tmux send-keys -t "$SESSION_NAME:build.0" "$cs_cmd ." Enter
	tmux split-window -h -t "$SESSION_NAME:build"
	tmux send-keys -t "$SESSION_NAME:build.1" "$cs_cmd ." Enter
	tmux split-window -v -t "$SESSION_NAME:build.1"
	tmux send-keys -t "$SESSION_NAME:build.2" "$cs_cmd .; clear" Enter
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

	tmux new-window -t "$SESSION_NAME" -n "claude"

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

	argparse 'a/allow' 'm/math' 'd/detach' -- $argv
	or return 1

	set -l detach (set -q _flag_d; and echo 1; or echo 0)
	set -l math_workspace (set -q _flag_m; and echo 1; or echo 0)
	set -l positionals $argv

	set -l assume_project_name (basename (pwd))
	if test -n "$positionals[1]"
		set assume_project_name $positionals[1]
	end

	set -l log_dir "$XDG_STATE_HOME/$assume_project_name/"

	#TODO!: make it use `script` to preserve coloring
	#DEPRECATE
	#tmux send-keys -t "$session_name:build.2" 'echo """$(gil)\n$(gifm)\n$(gifa)""" | less' Enter # all issues
	#DEPRECATE
	#tmux send-keys -t "$session_name:build.2" "nvim '+AnsiEsc' \"$log_dir/.log\"" Enter

	# `window`: cd
	if test $math_workspace = 1
		tmux send-keys -t "$session_name:window.0" "cd $log_dir" Enter
	else
		tmux send-keys -t "$session_name:window.0" "cd $log_dir && nvim window.toml" Enter
	end
	tmux send-keys -t "$session_name:window.1" "cd $log_dir && ~/.cargo/bin/window .log" Enter
	#TODO: run it in a loop (gets SIGBUS-terminated on overwrite of .log file)
	tmux send-keys -t "$session_name:window.2" "cd $log_dir && nvim '+AnsiEsc' .log..window" Enter

	if test $detach = 1
		echo $session_name
		return 0
	end

	tmux attach-session -t "$session_name:source.0"
end

# Rebuilds the working set recorded by `smart_shutdown` (`tmux_sessions.tsv` + `claude_restore.tsv`).
# Idempotent: sessions and claudes already live are skipped, so reruns (e.g. home-manager restarting the unit) are safe.
function restore_sessions
	argparse 'n/dry-run' -- $argv
	or return 1
	set -l state_home $XDG_STATE_HOME
	test -n "$state_home"; or set state_home "$HOME/.local/state"
	set -l sf "$state_home/tmux_sessions.tsv"
	set -l f "$state_home/claude_restore.tsv"
	for x in $sf $f
		if not test -f $x
			echo "restore_sessions: nothing to restore, $x absent (only smart_shutdown writes it)" >&2
			return 0
		end
	end

	set -l fresh # sessions built by this run, whose empty `claude` window takes the first claude
	set -l failed 0
	while read -l --delimiter \t name path
		if test -z "$path"
			echo "restore_sessions: malformed line in $sf: '$name	$path' (want '<session_name>	<session_path>')" >&2
			set failed 1
			continue
		end
		tmux has-session -t "=$name" 2>/dev/null; and continue
		if set -q _flag_dry_run
			echo "restore_sessions: would build $name at $path"
			set -a fresh $name
			continue
		end
		if not test -d $path
			echo "restore_sessions: skipping session $name — $path no longer a directory" >&2
			set failed 1
			continue
		end
		set -l built (cs -t -d $path)
		if test $status != 0
			echo "restore_sessions: cs -t -d $path failed: $built" >&2
			set failed 1
			continue
		end
		if not tmux rename-session -t "=$built" $name # `cs` names by dir; the recorded name carries renames and the `*` favorite
			echo "restore_sessions: could not rename $built to $name" >&2
			set failed 1
			continue
		end
		set -a fresh $name
		echo "restore_sessions: built $name at $path"
	end <$sf

	set -l live
	for s in $HOME/.claude*/sessions/*.json
		test -d /proc/(jq -r .pid $s); and set -a live (jq -r .sessionId $s)
	end

	set -l done 0
	while read -l --delimiter \t session cwd id config_dir
		if test -z "$config_dir"; or not string match -qr '^[0-9a-f-]{36}$' -- "$id"
			echo "restore_sessions: malformed line in $f: '$session	$cwd	$id	$config_dir' (want '<session_name>	<cwd>	<session_id>	<config_dir>')" >&2
			set failed 1
			continue
		end
		if contains -- $id $live
			echo "restore_sessions: $id already live, skipping"
			continue
		end
		if not test -d $cwd
			echo "restore_sessions: skipping $id — $cwd no longer a directory" >&2
			set failed 1
			continue
		end
		set -l acc
		if test "$config_dir" != "$HOME/.claude"
			set acc (string replace -r "^$HOME/\.claude-account" '' -- $config_dir)
			if not string match -qr '^[0-9]+$' -- $acc
				echo "restore_sessions: $id — unknown config dir $config_dir" >&2
				set failed 1
				continue
			end
			set acc --acc $acc
		end
		set -l cmd "cd "(string escape -- $cwd)"; and cl --resume $id $acc"

		if set -q _flag_dry_run
			echo "restore_sessions: would run in $session: $cmd"
			continue
		end
		if not tmux has-session -t "=$session" 2>/dev/null
			echo "restore_sessions: $id — session $session neither live nor rebuilt" >&2
			set failed 1
			continue
		end
		set -l target "=$session:claude"
		if set -l i (contains -i -- $session $fresh)
			set -e fresh[$i]
		else
			set target (tmux new-window -P -F '#{pane_id}' -t "=$session:" -c $cwd -n claude)
			if test $status != 0
				echo "restore_sessions: $session — could not add claude window: $target" >&2
				set failed 1
				continue
			end
		end
		if not tmux send-keys -t $target $cmd Enter
			echo "restore_sessions: $session — send-keys to '$target' failed" >&2
			set failed 1
			continue
		end
		set done (math $done + 1)
		echo "restore_sessions: $session ← $id ($cwd)"
	end <$f

	if test $failed = 1
		echo "restore_sessions: some entries failed; keeping $f so a rerun can retry" >&2
		return 1
	end
	echo "restore_sessions: restored $done claude(s); keeping $f for future restores"
end
