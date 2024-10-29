source /home/v/s/g/private/credentials.fish
source (dirname (status --current-filename))/global.fish #NB: other things can rely on functions in it
source (dirname (status --current-filename))/other.fish

source (dirname (status --current-filename))/cli_translate.fish
source (dirname (status --current-filename))/cs_nav.fish

source (dirname (dirname (dirname (status --current-filename))))/scripts/mod.fish

source (dirname (status --current-filename))/app_aliases/mod.fish

source /etc/nixos/home/file_snippets/main.fish
source /etc/nixos/home/scripts/shell_harpoon/main.fish
alias up="/etc/nixos/home/scripts/maintenance/main.sh"

# # Init utils
zoxide init fish | source
starship init fish | source

atuin init fish --disable-up-arrow --disable-ctrl-r | source
export filter_mode_shell_up_key_binding="directory"
bind \cr "_atuin_bind_up" # only for current dir
bind \cg "_atuin_search" # global search
# and then the actual Up is searching through the session history, as is the default.
#
