# tmux config

- `tmux.conf` — tmux configuration.
- `claude_sessions.rs` — cargo-script that reports the state of every Claude Code
  process running in a tmux window (used by the status line / eww widget). Run
  via `nix-run-cached`; aliased to `claude_sessions` in `__main__.fish`.
- `switch_to_last_session.sh` — helper bound in `tmux.conf`.
- `tests/` + `snapshots/` — snapshot tests for the `claude_sessions.rs` terminal
  state classifier, plus `tests/reports/` for the closing-report judge (see below).

## Closing-report verdicts

A pane reading `finished` only means Claude stopped talking. `mod report` inside
`claude_sessions.rs` takes the session's closing report (the last assistant turn
in the transcript) and has an LLM — via the `ask_llm` crate — judge it as
`finished` / `stuck` / `partial`, which become states of their own: `stuck` is
colored like `question`, `partial` like `error`.

The verdict is cached in `~/.cache/claude-session-reports.json` against the
transcript's mtime, so it costs one call per session settle, not one per
status-line refresh. Misses are cached too — an unreachable model must not earn
a doomed HTTP call on every refresh — and retried on the session's next turn. No
`CLAUDE_TOKEN` in the environment turns the whole thing off and every settled
session just reads `finished`. `done` panes (untouched for 45 min) are never
classified — that signal has already decayed.

The judging prompt is the whole classifier, so it's pinned by
`tests/reports/<verdict>__<desc>.md` — real closing reports, one live call each,
same drop-a-file-in-and-it's-covered deal as the pane fixtures. Editing the
prompt invalidates every cached verdict (they were drawn by a different judge).

The model is meant to be DeepSeek (`ask_llm::Model::DeepSeek`, added in the
unreleased 2.2.3); the account is out of balance and 402s every call, so it runs
on `Model::Fast` (Haiku) meanwhile. Switching back is one line in `report::ask`
plus an `ask_llm` version bump once 2.2.3 is published.

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
draft case) into a `ClaudeState` (`empty / active / planning / finished / draft /
question / input / error / limit`). Everything else in the script is live-environment I/O (`tmux
list-panes`, `/proc`, `pgrep`, the OAuth usage endpoint, ollama) and is **not**
unit-tested — it can't be exercised honestly without mocks or a full e2e tmux
harness.

Each test case is a **real captured pane** stored under `tests/fixtures/`, with
its expected state encoded in the filename and its full result pinned by an
`insta` snapshot in `snapshots/`. No mocks.

`finished`, `empty`, and `input` are deliberately **not** held apart with any
precision — they're treated as interchangeable "nothing's blocked, nothing's
running" states. `input` (user typed into the box but hasn't sent) is detected
loosely: a non-empty input line under the `(shift+tab to cycle)` mode footer.
Its only job is to keep a typed numbered list (`❯ 1. …`) from being misread as a
`question` selector, and to color such panes white (same as `limit`). A finished
session showing a dim ghost suggestion may read as `input`; that's fine.

## Adding a test case

When a pane gets classified wrong, capture it and drop it in — no code change
needed. See `tests/fixtures/README.md` for the full workflow; the short version:

```fish
tmux capture-pane -t <session>:<window> -p -S -50 > tests/fixtures/<state>__<desc>.txt
INSTA_UPDATE=always claude_sessions_test   # record its snapshot
claude_sessions_test                        # confirm green
```

`<state>` is one of `empty active planning finished draft question error`. For draft cases
also capture the escape-coded pane to `tests/fixtures/<state>__<desc>.esc`
(`tmux capture-pane -p -e -S -10`) — it's how typed input is told apart from grey
ghost suggestions.
