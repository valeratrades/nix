# Project scaffolding alias - wrapping new_project.rs
# See legacy_main.fish for the original fish implementation (kept for reference)

set __fish_file_snippets_dir (status dirname)
function new_project; $__fish_file_snippets_dir/new_project.rs $argv; end
