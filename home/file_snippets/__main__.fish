# Project scaffolding alias - wrapping new_project.rs
# See legacy_main.fish for the original fish implementation (kept for reference)

set __fish_file_snippets_dir (dirname (status --current-filename))
alias new_project="$__fish_file_snippets_dir/new_project.rs"
