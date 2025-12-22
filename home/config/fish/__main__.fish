#NB: don't make aliases with """,""" - as they are incorrectly interpreted
#NB: local vars are shared between all things you source. So setting an abbreviation to say `(dirname(status -- curent-filename))` to something simple like `pdir` could overwrite pdir of something else and wreck havoc.

set main_config_pdir (dirname (status --current-filename))

source $HOME/s/g/private/credentials.fish
source $main_config_pdir/global.fish #NB: other things can rely on functions in it
source $main_config_pdir/other.fish

source $main_config_pdir/cli_translate.fish
source $main_config_pdir/cs_nav.fish
source $main_config_pdir/tmp.fish

source (dirname (dirname $main_config_pdir))/scripts/__main__.fish

source $main_config_pdir/app_aliases/__main__.fish

source "$NIXOS_CONFIG/home/file_snippets/__main__.fish"
source "$NIXOS_CONFIG/home/scripts/shell_harpoon/main.fish"

# Init utils {{{
## optional {{{
if command -v zoxide &>/dev/null
	zoxide init fish | source
end
if command -v todo &>/dev/null
	todo init fish | source
end
if command -v tg &>/dev/null
	tg init fish 2>/dev/null | source
end
if command -v himalaya &>/dev/null
	himalaya completion fish | source
end
if command -v watchexec &>/dev/null
	watchexec --completions fish | source
end
if command -v shuttle &>/dev/null
	shuttle generate shell fish | source
	shuttle generate manpage > "$XDG_DATA_HOME/man/man1/shuttle.1"
end
##,}}}
atuin init fish --disable-up-arrow --disable-ctrl-r | source
bind \cr "_atuin_bind_up" # configured in $XDG_CONFIG_HOME/atuin/config.toml
bind \cg "_atuin_search" # global search

starship init fish --print-full-init | source # somehow fixes the psub bug that happens when using tmux with my config, initiated via standard nixos's `enable`
#,}}}

set -g MANPATH "$XDG_DATA_HOME/man:$MANPATH";
mkdir -p "$XDG_DATA_HOME/man/man1/"
