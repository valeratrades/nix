# Everything can rely on functions from here

function exa --wraps eza; eza $argv; end
function ls; command ls --color=tty $argv; end
function ll --wraps 'ls -l'; ls -l $argv; end
function l --wraps 'ls -alh'; ls -alh $argv; end

# for super ls
function sl
    if test -f "$argv[1]"
        bat $argv[1]
    else
        exa -Ah $argv
    end
end

function lt --wraps 'eza --sort new'; eza --sort new $argv; end

function mkfile
    set file_path "$argv[1]"
    mkdir -p (dirname "$file_path")
    touch "$file_path"
end
function mkf --wraps mkfile; mkfile $argv; end

function cs
    argparse 't/tmux' 'm/math' 'a/allow' 'd/detach' -- $argv
    or return 1

    if set -q _flag_t
        if test (count $argv) -gt 0
            direnv deny "$argv[1]"
            cd "$argv[1]" || return 1
        end
        if set -q _flag_m
            tn -a -m (set -q _flag_d; and echo -n -d)
        else if set -q _flag_d
            tn -a -d
        else
            tn -a
        end
        return
    end

    if set -q _flag_m
        if test (count $argv) -gt 0
            cd "$argv[1]" || return 1
        end
        typst_workspace
        return
    end

    if test (count $argv) -gt 0; and test -f "$argv[1]"
        e "$argv[1]"
    else
        if test (count $argv) -gt 0
            cd "$argv" || return 1
        end

        if set -q _flag_a
            direnv allow
        end
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

function pu
    $HOME/s/help_scripts/pip_upload.sh
end

function pt --wraps pytest; pytest $argv; end
function pk --wraps 'pytest -k'; pytest -k $argv; end
function pm --wraps 'py src/main.py'; py src/main.py $argv; end

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
