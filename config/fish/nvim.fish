# nvim shortcut, that does cd first, to allow for harpoon to detect project directory correctly
# e stands for editor
#NB: $1 nvim arg has to be the path
function e
    set -l nvim_commands ""
    if test "$argv[1]" = "--flag_load_session"
        set nvim_commands "-c SessionLoad"
        set argv (status --current-args | cut -d' ' -f2-)
    end

    set -l nvim_evocation "nvim"
    if test "$argv[1]" = "--use_sudo_env"
        set nvim_evocation "sudo -Es -- nvim"
        set argv (status --current-args | cut -d' ' -f2-)
    end

    #git_push_after="false"
    # if [ "$1" = "--git_sync" ]; then
    #	git_push_after="true"
    #	shift
    #	git -C "$1" pull > /dev/null 2>&1
    #fi

    set -l full_command "$nvim_evocation ."
    if test -n "$argv[1]"
        if test -d "$argv[1]"
            pushd "$argv[1]" > /dev/null
            set argv (status --current-args | cut -d' ' -f2-)
            set full_command "$nvim_evocation $argv ."
        else
            set -l could_fix 0
            set -l try_extensions "" .sh .rs .go .py .json .txt .md .typ .tex .html .js .toml .conf
            # note that indexing starts at 1, as we're in a piece of shit zsh.
            for ext in $try_extensions
                set -l try_path "$argv[1]$ext"
                if test -f "$try_path"
                    pushd (dirname "$try_path") > /dev/null
                    set argv (status --current-args | cut -d' ' -f2-)
                    set full_command "$nvim_evocation (basename "$try_path") $argv $nvim_commands"
                    eval $full_command
                    popd > /dev/null
                    # if git_push_after; then
                    #	push ${1}
                    #fi
                    return 0
                end
            end
            set full_command "$nvim_evocation $argv"
        end
    end

    set full_command "$full_command $nvim_commands"
    eval $full_command

    # clean the whole dir stack, which would drop back if `pushd` was executed, and do nothing otherwise.
    # hopefuly I'm not breaking anything by doing so.
    while test (count (dirs)) -gt 1
        popd
    end

    # if [ "$git_push_after" = "true" ]; then
    #	push ${1}
    #fi
end

function ep
    e --flag_load_session $argv
end
function se
    e --use_sudo_env $argv
end
alias ec="e ~/.config/nvim"
alias es="nvim ~/.config/fish/main.fish"
alias ezt="e ~/.config/zsh/theme.zsh"
alias epy="e ~/envs/Python/lib/python3.11/site-packages"
alias et="nvim /tmp/a_temporary_note.md -c 'nnoremap q gg^vG^g_\"+y:qa!<CR>' -c 'startinsert'"

# to simplify pasting stuff
alias vi="nvim"
alias vim="nvim"
