#!/usr/bin/env fish
# Usage: notify.fish <label>
# Reads Claude hook JSON from stdin and sends a beep notification.
# Debounces to at most one notification per session per 5 seconds.

set label $argv[1]

read input
set session_id (echo $input | jq -r .session_id)
set stamp_file /tmp/claude-notify-$label-$session_id
set now (date +%s)

if test -f $stamp_file
    set last (cat $stamp_file)
    if test (math $now - $last) -lt 5
        exit 0
    end
end

echo $now > $stamp_file

set transcript_path (echo $input | jq -r .transcript_path)
set chat_name (head -1 $transcript_path | jq -r .summary)
set tmux_session (tmux display-message -p "#S" 2>/dev/null || echo "no session")
set cwd (echo $input | jq -r .cwd)

beep -l=15 "CC: $label on:\n$tmux_session\n$chat_name\n$cwd"
