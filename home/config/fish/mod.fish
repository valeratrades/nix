#NB: don't make aliases with """,""" - as they are incorrectly interpreted
set pdir (dirname (status --current-filename))

source /home/v/s/g/private/credentials.fish
source $pdir/global.fish #NB: other things can rely on functions in it
source $pdir/other.fish

source $pdir/cli_translate.fish
source $pdir/cs_nav.fish

source (dirname (dirname $pdir))/scripts/mod.fish

source $pdir/app_aliases/mod.fish

source "$NIXOS_CONFIG/home/file_snippets/main.fish"
source "$NIXOS_CONFIG/home/scripts/shell_harpoon/main.fish"

# # Init utils
zoxide init fish | source

atuin init fish --disable-up-arrow --disable-ctrl-r | source
export filter_mode_shell_up_key_binding="directory"
bind \cr "_atuin_bind_up" # only for current dir
bind \cg "_atuin_search" # global search
# and then the actual Up is searching through the session history, as is the default.
#
