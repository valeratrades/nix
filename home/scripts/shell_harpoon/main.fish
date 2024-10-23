set harpoon_config_path "$HOME/s/help_scripts/shell_harpoon/config.fish"

function mute
    nohup alacritty -e nvim "$harpoon_config_path" \
        -c "nnoremap q :q<CR>" -c "nnoremap <esc> :q<CR>" -c "autocmd QuitPre * :w" > /dev/null 2>&1 &
    sleep 0.35
    swaymsg floating enable

    wait $last_pid
end

function ,ui
    mute > /dev/null 2>&1
end

set temp_file "$HOME/tmp/shell_harpoon.fish"

function ,set
    set dir (pwd)
    if test -n "$argv[1]"
        set dir "$dir/$argv[1]"
    end
    mkdir -p (dirname "$temp_file")
    echo "set -x SHELL_HARPOON_CURRENT_DIR_DUMP (pwd)" > "$temp_file"
    source $temp_file
end

# open nvim and cache the dir
function ,e
    ,add $argv
    e $argv
end

function e,
    set _current_dir (pwd)
    ,c
    e . $argv
    cd $_current_dir
end

function ,c
    if not test -n "$SHELL_HARPOON_CURRENT_DIR_DUMP"
        printf "Error: first dump the current dir by doing \033[34m,add\033[0m\n"
        return 1
    else
        source $temp_file
        if type -q "cs"
            cs $SHELL_HARPOON_CURRENT_DIR_DUMP
        else
            cd $SHELL_HARPOON_CURRENT_DIR_DUMP
        end
    end
end

source $harpoon_config_path
if test -e "$temp_file"
    source $temp_file
end

alias ,s="source $harpoon_config_path; and _s"
alias ,r="source $harpoon_config_path; and _r"
alias ,n="source $harpoon_config_path; and _n"
alias ,t="source $harpoon_config_path; and _t"
