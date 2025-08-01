# Everything can rely on functions from here

alias exa="eza"

# for super ls
function sl
    if test -f "$argv[1]"
        bat $argv[1]
    else
        exa -Ah $argv
    end
end

alias lt="eza --sort new"

function mkfile
    set file_path "$argv[1]"
    mkdir -p (dirname "$file_path")
    touch "$file_path"
end
alias mkf="mkfile"

function cs
    if test -f "$argv[1]"
        e "$argv[1]"
    else
        cd "$argv" || return 1

        source "./.local.fish" > /dev/null 2>&1 || true
        source "./tmp/.local.fish" > /dev/null 2>&1 || true

        if test -n "$VIRTUAL_ENV"
            deactivate
            set -e VIRTUAL_ENV
        end

        sl
    end
end

# go
function go
    todo manual counter-step --dev-runs
    /usr/bin/env go $argv
end

# python
function py
    todo manual counter-step --dev-runs
    python $argv
end

function spy
    todo manual counter-step --dev-runs
    sudo python $argv
end

function pp
    pip $argv --break-system-packages
end

function pu
    $HOME/s/help_scripts/pip_upload.sh
end

alias pt="pytest"
alias pk="pytest -k "
alias pm="py src/main.py"

# Adjust font size in Alacritty
function fontsize
    set CONFIG_FILE "$HOME/.config/alacritty/alacritty.toml"

    if test -z "$argv[1]"
        set current_size (grep '^size = ' "$CONFIG_FILE" | sed 's/size = //')
        echo "$current_size"
    else
        sed -i 's/^\(size = \).*/\1'"$argv[1]"'/' "$CONFIG_FILE"
    end
end

function mkcd
    mkdir -p "$argv[1]" && cd "$argv[1]"
end

function mvcd
    mv $argv && cd (basename "$argv[-1]")
end

function git_upload
	if test (count $argv) -lt 1
		echo "Usage: git_upload <repository_root> [commit_message...]"
		return 1
	end

	set repository_root $argv[1]

	set commit_msg (string join " " $argv[2..-1])
		if test "$commit_msg" = ""
		set commit_msg "_"
	end

	git -C "$repository_root" add -A \
	&& git -C "$repository_root" commit -m "$commit_msg" \
	&& git -C "$repository_root" push
end
