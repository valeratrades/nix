#!/bin/bash
set -e

todo_root="$HOME/Documents/notes/personal/todo_list"
directory=$(date +%d-%b-%y | tr '[:upper:]' '[:lower:]')

if [ ! -d "$todo_root/$directory" ]; then
    mkdir -p "$todo_root/$directory"
    title="$(date +'%B %d, %Y')"
    underline=$(echo "$title" | sed "s/./=/g")
    echo -e "$title\n$underline\n\nTodo\n----\n\nCompleted\n---------" \
        >> "$todo_root/$directory/index.md"

    if [ $(date +%d) -eq "01" ]; then
        month=$(date +%B)
        underline=$(echo "$month" | sed 's/./-/g')
        echo -e "\n$month\n$underline" >> "$todo_root/index.md"
    fi
    echo "($title)[$directory/index.md]" >> "$todo_root/index.md"

fi

"$HOME/.config/tmux/popup.sh" "$EDITOR $todo_root/$directory/index.md"
