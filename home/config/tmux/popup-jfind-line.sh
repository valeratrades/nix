#!/bin/bash
set -e

disable_cursor='echo "\x1b[?25l"'
"$HOME/.config/tmux/popup.sh" "$disable_cursor; $HOME/.config/jfind/jfind-line.sh '$1'; $disable_cursor"
