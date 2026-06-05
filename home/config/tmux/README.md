# tmux config

- `tmux.conf` — tmux configuration.
- `claude_sessions.rs` — cargo-script that reports the state of every Claude Code
  process running in a tmux window (used by the status line / eww widget). Run
  via `nix-run-cached`; aliased to `claude_sessions` in `__main__.fish`.
- `switch_to_last_session.sh` — helper bound in `tmux.conf`.
- `tests/` + `snapshots/` — snapshot tests for the `claude_sessions.rs` terminal
  state classifier (see below).

## Running the tests

The tests live inside `claude_sessions.rs` itself (it's a single-file
cargo-script). The simplest way — a fish helper from `__main__.fish` wraps the
nightly-toolchain resolution:

```fish
claude_sessions_test
```

Extra args pass through to `cargo test`, e.g.:

```fish
claude_sessions_test -- --nocapture
INSTA_UPDATE=always claude_sessions_test   # record snapshots for new fixtures
```

If you'd rather not go through the helper, the raw invocation is:

```fish
set RUST_PATH (cat ~/.cargo/target/.rust-store-path)
env RUSTC_WRAPPER="" PATH="$RUST_PATH/bin:$PATH" \
    cargo -Zscript test --manifest-path ./claude_sessions.rs
```

(`RUSTC_WRAPPER=""` disables sccache; the `PATH` prefix points cargo at the
nix-pinned nightly the runner already cached.)

## What the tests cover

Only the part that actually regresses: `classify_activity` — the pure function
that turns a captured tmux pane (plain text, plus an escape-coded capture for the
draft case) into a `ClaudeState` (`empty / active / finished / draft / question /
error`). Everything else in the script is live-environment I/O (`tmux
list-panes`, `/proc`, `pgrep`, the OAuth usage endpoint, ollama) and is **not**
unit-tested — it can't be exercised honestly without mocks or a full e2e tmux
harness.

Each test case is a **real captured pane** stored under `tests/fixtures/`, with
its expected state encoded in the filename and its full result pinned by an
`insta` snapshot in `snapshots/`. No mocks.

## Adding a test case

When a pane gets classified wrong, capture it and drop it in — no code change
needed. See `tests/fixtures/README.md` for the full workflow; the short version:

```fish
tmux capture-pane -t <session>:<window> -p -S -50 > tests/fixtures/<state>__<desc>.txt
INSTA_UPDATE=always claude_sessions_test   # record its snapshot
claude_sessions_test                        # confirm green
```

`<state>` is one of `empty active finished draft question error`. For draft cases
also capture the escape-coded pane to `tests/fixtures/<state>__<desc>.esc`
(`tmux capture-pane -p -e -S -10`) — it's how typed input is told apart from grey
ghost suggestions.
