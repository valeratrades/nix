#NB: don't make aliases with """,""" - as they are incorrectly interpreted
#NB: local vars are shared between all things you source. So setting an abbreviation to say `(dirname(status -- curent-filename))` to something simple like `pdir` could overwrite pdir of something else and wreck havoc.

set __fish_config_main_dir (status dirname)

test -f $HOME/s/g/private/credentials.fish; and source $HOME/s/g/private/credentials.fish # absent on servers

# sops secrets are written for systemd (`writeSecretsEnvd` in hosts/v-laptop/home.nix), and
# environment.d is read by user *units* only - sway is exec'd from this shell, not from a unit.
if test -f $HOME/.config/environment.d/30-secrets.conf
    for __secret_line in (string match -r '^[^=]+=.*' < $HOME/.config/environment.d/30-secrets.conf)
        set -gx (string split -m1 = -- $__secret_line)
    end
    set -e __secret_line
end

# not in conf.d/: fish sources conf.d *before* this file, so sway and everything it spawns would
# inherit an env without the credentials above.
# redirect: sway's startup/DRM/renderer errors go to a persistent file instead of vanishing on
# tty1, so a failed boot is diagnosable from the rollback (journal never sees it). `-d` comes from
# the NixOS sway wrapper when vars `debug` is set (os/nixos/desktop/programs/sway.nix).
string match -q /dev/tty1 -- (path resolve /proc/self/fd/0); and exec sway 2>$HOME/.sway.log

source $__fish_config_main_dir/global.fish #NB: other things can rely on functions in it
source $__fish_config_main_dir/other.fish

source $__fish_config_main_dir/cli_translate.fish
source $__fish_config_main_dir/cs_nav.fish
source $__fish_config_main_dir/tmp.fish

source $__fish_config_main_dir/../../scripts/__main__.fish

source $__fish_config_main_dir/app_aliases/__main__.fish

source $__fish_config_main_dir/../../file_snippets/__main__.fish
#source "$NIXOS_CONFIG/home/scripts/shell_harpoon/main.fish" #DEPRECATED: pointless. Might want to nuke the entire thing
source $__fish_config_main_dir/../eww/__main__.fish
source $__fish_config_main_dir/../tmux/__main__.fish

# Init utils {{{

# Cached shell init primitive - caches output of slow init commands
# Usage: cached_init <cache_name> <command...>
# Refresh all caches by calling: refresh_shell_init_caches
set -g __shell_init_cache_dir "$XDG_CACHE_HOME/fish/shell_init"

function cached_init
    set -l cache_name $argv[1]
    set -l cmd $argv[2..-1]
    set -l cache_file "$__shell_init_cache_dir/$cache_name.fish"

    if test -f "$cache_file"
        source "$cache_file"
    else
        # Cache miss - generate and cache
        mkdir -p "$__shell_init_cache_dir"
        eval $cmd > "$cache_file" 2>/dev/null
        source "$cache_file"
    end
end

function refresh_shell_init_caches
    echo "Refreshing shell init caches..."
    rm -rf "$__shell_init_cache_dir"
    mkdir -p "$__shell_init_cache_dir"

    if command -v zoxide &>/dev/null
        echo "  zoxide..."
        zoxide init fish --no-cmd > "$__shell_init_cache_dir/zoxide_no_cmd.fish"
    end
    if command -v atuin &>/dev/null
        echo "  atuin..."
        atuin init fish --disable-up-arrow --disable-ctrl-r > "$__shell_init_cache_dir/atuin.fish" 2>/dev/null
    end
    if command -v starship &>/dev/null
        echo "  starship..."
        starship init fish --print-full-init > "$__shell_init_cache_dir/starship.fish" 2>/dev/null
    end

    echo "Done. Restart shell to apply."
end

## optional {{{
if command -v zoxide &>/dev/null
    cached_init zoxide_no_cmd "zoxide init fish --no-cmd" # --no-cmd: its `--cmd` defines z/zi via `alias`
    function z --wraps __zoxide_z; __zoxide_z $argv; end
    function zi --wraps __zoxide_zi; __zoxide_zi $argv; end
end
# completion-and-alias-only inits (tedi, tg, discretionary_engine, shuttle) are baked into their packages for autoload: home/config/fish/with_fish_init.nix
##,}}}
# pre-empts the init's `(atuin uuid)` with the same condition; v7 because atuin reads its timestamp as session start
if not set -q ATUIN_SESSION; or test "$ATUIN_SHLVL" != "$SHLVL"
    read -l uuid_v4 </proc/sys/kernel/random/uuid
    set -gx ATUIN_SESSION (printf %012x (math (path mtime /proc/self) \* 1000))7(string sub -s 14 (string replace -a - '' $uuid_v4)) # shortcut: second-precision timestamp, fish has no finer builtin clock
    set -gx ATUIN_SHLVL $SHLVL
end
cached_init atuin "atuin init fish --disable-up-arrow --disable-ctrl-r"
bind \cr "_atuin_bind_up" # configured in $XDG_CONFIG_HOME/atuin/config.toml
bind \cg "_atuin_search" # global search

# atuin's own preexec blocks every command on a synchronous `atuin history start`; record start+end in one detached job after the command instead.
# Cost: the entry's timestamp is the command's end, not its start.
functions -e _atuin_preexec _atuin_postexec
function __atuin_remember_cwd --on-event fish_preexec
    set -g __atuin_cwd $PWD # `cd` would otherwise be recorded under its target
end
function __atuin_record --on-event fish_postexec
    set -l code $status
    test -n "$fish_private_mode"; and return
    # never-valid invocations stay out of history: 64 EX_USAGE, 65 EX_DATAERR, 126 not executable, 127 not found
    contains $code 64 65 126 127; and return
    ATUIN_LOG=error command sh -c 'cd "$1" && id=$(atuin history start -- "$4") && [ -n "$id" ] && atuin history end --exit "$2" --duration "$3" "$id"' _ $__atuin_cwd $code "$CMD_DURATION"000000 $argv[1] &>/dev/null &
    disown
end

cached_init starship "starship init fish --print-full-init" # somehow fixes the psub bug that happens when using tmux with my config, initiated via standard nixos's `enable`
#,}}}

set -g MANPATH "$XDG_DATA_HOME/man:$MANPATH";
