#NB: don't make aliases with """,""" - as they are incorrectly interpreted
#NB: local vars are shared between all things you source. So setting an abbreviation to say `(dirname(status -- curent-filename))` to something simple like `pdir` could overwrite pdir of something else and wreck havoc.

set main_config_pdir (dirname (status --current-filename))

source $HOME/s/g/private/credentials.fish
source $main_config_pdir/global.fish #NB: other things can rely on functions in it
source $main_config_pdir/other.fish

source $main_config_pdir/cli_translate.fish
source $main_config_pdir/cs_nav.fish

source (dirname (dirname $main_config_pdir))/scripts/mod.fish

source $main_config_pdir/app_aliases/mod.fish

source "$NIXOS_CONFIG/home/file_snippets/main.fish"
source "$NIXOS_CONFIG/home/scripts/shell_harpoon/main.fish"

# # Init utils
zoxide init fish | source
todo init fish | source

starship init fish --print-full-init | source # somehow fixes the psub bug that happens when using tmux with my config, initiated via standard nixos's `enable`

atuin init fish --disable-up-arrow --disable-ctrl-r | source
export filter_mode_shell_up_key_binding="directory"
bind \cr "_atuin_bind_up" # only for current dir
bind \cg "_atuin_search" # global search
# and then the actual Up is searching through the session history, as is the default.
#
