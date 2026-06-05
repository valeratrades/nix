set __fish_config_tmux_dir (dirname (status --current-filename))
alias claude_sessions="$__fish_config_tmux_dir/claude_sessions.rs"

# Run the claude_sessions.rs classifier snapshot tests. Wraps the nightly
# toolchain resolution the cargo-script runner already cached, so you don't
# retype the RUST_PATH/PATH dance. Extra args pass straight through to cargo,
# e.g. `claude_sessions_test -- --nocapture`. Set INSTA_UPDATE=always to
# record snapshots for newly added fixtures.
function claude_sessions_test
    set -l rust_path (cat $HOME/.cargo/target/.rust-store-path)
    env RUSTC_WRAPPER="" PATH="$rust_path/bin:$PATH" \
        "$rust_path/bin/cargo" -Zscript test \
        --manifest-path "$__fish_config_tmux_dir/claude_sessions.rs" $argv
end
