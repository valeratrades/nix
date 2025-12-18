# Project scaffolding alias - wrapping new_project.rs
# See legacy_main.fish for the original fish implementation (kept for reference)

set -l _pdir (dirname (status --current-filename))
alias new_project="$_pdir/new_project.rs"
