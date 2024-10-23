#alias tmux="TERM='alacritty-direct' tmux"
alias ta="tmux attach -t"
alias tl="tmux ls"
alias tk="tmux kill-session -t"
alias tks="tmux kill-server"

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

    # Ref window
    tmux new-window -t "$SESSION_NAME" -n "ref"

    # Tmp window
    tmux new-window -t "$SESSION_NAME" -n "tmp"
    tmux send-keys -t "$SESSION_NAME:tmp.0" 'cd tmp; clear' Enter
    tmux split-window -h -t "$SESSION_NAME:tmp"
    tmux send-keys -t "$SESSION_NAME:tmp.1" 'cd tmp; clear' Enter
    tmux split-window -v -t "$SESSION_NAME:tmp.1"
    tmux send-keys -t "$SESSION_NAME:tmp.2" 'cd tmp; clear' Enter
    tmux send-keys -t "$SESSION_NAME:tmp.0" 'nvim .' Enter
    tmux select-pane -t "$SESSION_NAME:tmp.0"

    return "$SESSION_NAME"
end

function tn
    #! Github issues init
    set -l session_name_or_err (tmux_new_session_base $argv)
    if test $status = 1
        echo $session_name_or_err
        return 1
    end
    set -l session_name $session_name_or_err

    tmux send-keys -t "$session_name:build.2" 'gil' Enter # all issues
    tmux send-keys -t "$session_name:build.2" 'gifm' Enter # issues of current milestone
    tmux send-keys -t "$session_name:build.2" 'gifa' Enter # issues of current milestone that I am working on

    tmux attach-session -t "$session_name:source.0"
end

function tn2
    #! Cargo Watch + log init
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

    tmux send-keys -t "$session_name:build.0" 'c t' Enter
    tmux send-keys -t "$session_name:build.1" "cd ~/.{assume_project_name} && nvim .log" Enter
    tmux send-keys -t "$session_name:build.2" 'cw' Enter

    tmux new-window -t "$session_name" -n "window"
    tmux send-keys -t "$session_name:window.0" "cd ~/.{assume_project_name} && nvim window.toml" Enter
    tmux split-window -h -t "$session_name:window"
    tmux send-keys -t "$session_name:window.1" "cd ~/.{assume_project_name} && nvim .log..window" Enter
    tmux split-window -v -t "$session_name:window.0"
    tmux send-keys -t "$session_name:window.1" "cd ~/.{assume_project_name} && window .log" Enter
    tmux select-pane -t "$session_name:window.0"

    tmux attach-session -t "$session_name:source.0"
end
