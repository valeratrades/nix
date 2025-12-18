# Project scaffolding aliases - wrapping main.rs
# See legacy_main.fish for the original fish implementation (kept for reference)

set -g project_new_script "$NIXOS_CONFIG/home/file_snippets/main.rs"

alias can="$project_new_script can"
alias pyn="$project_new_script pyn"
alias gon="$project_new_script gon"
alias lnn="$project_new_script lnn"
alias tyn="$project_new_script tyn"
