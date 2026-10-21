set __fish_config_tmux_dir (status dirname)
function claude_sessions; $__fish_config_tmux_dir/claude_sessions.rs $argv; end

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

# tmux panes outlive a sway restart, keeping SWAYSOCK of the dead compositor
function __swaysock_refresh --on-event fish_preexec
    set -q SWAYSOCK; and not test -S $SWAYSOCK; or return
    for sock in $XDG_RUNTIME_DIR/sway-ipc.*.sock
        test -d /proc/(string split . -- $sock)[-2]; or continue # a crashed sway leaves its socket behind
        set -gx SWAYSOCK $sock
        return
    end
end
