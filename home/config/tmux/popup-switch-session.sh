disable_cursor='echo "\x1b[?25l"'
"$HOME/.config/tmux/popup.sh" \
    "$disable_cursor; $HOME/.config/tmux/switch-session.sh; $disable_cursor" "-B"

