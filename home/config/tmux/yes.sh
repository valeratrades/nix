identifier="$1"
pidfile="/tmp/tmux_yes_$identifier"

if [ -e "$pidfile" ]; then
    pid=$(cat "$pidfile")
    if ps -p $pid > /dev/null; then
        kill $pid
    fi
    rm "$pidfile"
else
    echo $$ > "$pidfile"
    trap 'rm -f "$pidfile"; exit' INT TERM EXIT

    while tmux send-keys -t "$1" Enter; do
        sleep 1
    done
fi
