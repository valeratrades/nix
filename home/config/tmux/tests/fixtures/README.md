# Terminal-state classifier fixtures

Each `*.txt` here is a **real `tmux capture-pane -p` dump** of a Claude Code pane.
The test in `claude_sessions.rs` (`mod tests`) feeds every one through the pure
`classify_activity` function and checks that:

1. the resulting `ClaudeState` equals the `<state>__` prefix in the filename, and
2. the full `ActivityResult` matches its recorded `insta` snapshot in `../../snapshots/`.

No tmux / `/proc` / network / mocks are involved — just text in, state out.

## Naming

```
<state>__<description>.txt        # plain capture-pane -p
<state>__<description>.esc        # OPTIONAL: capture-pane -p -e (only the draft path reads it)
<state>__<description>.jsonl      # OPTIONAL: session transcript tail (only the active↔finished deliberation reads it)
```

`<state>` ∈ `empty active finished draft question input error limit interrupted`.

A `.jsonl` companion means the pane text alone reads Finished and the transcript
arbitrates; `<state>` then names the FINAL verdict. The same pane dump can back
both an `active__*` and a `finished__*` fixture with different transcript tails.

## Add a new case (no code edit needed)

When you hit a pane that classifies wrong — or want to lock in a tricky one —
capture it live and drop it in:

```fish
# from this directory
tmux capture-pane -t <session>:<window> -p -S -50 > question__some_widget.txt

# ONLY for draft cases (typed-vs-ghost-suggestion needs the escape-coded capture):
tmux capture-pane -t <session>:<window> -p -e -S -10 > draft__typed.esc

# ONLY for active/finished deliberation cases (idle-looking pane, transcript decides):
tail -n 15 ~/.claude/projects/<proj-dir>/<session-id>.jsonl > finished__idle.jsonl
```

Then record its snapshot and confirm it's green:

```fish
set RUST_PATH (cat ~/.cargo/target/.rust-store-path)
env RUSTC_WRAPPER="" PATH="$RUST_PATH/bin:$PATH" INSTA_UPDATE=always cargo -Zscript test --manifest-path ../../claude_sessions.rs
env RUSTC_WRAPPER="" PATH="$RUST_PATH/bin:$PATH" INSTA_UPDATE=no     cargo -Zscript test --manifest-path ../../claude_sessions.rs
```

The filename-prefix assertion runs automatically; the snapshot pins the extracted
draft/question text so subtler drift (wrong truncation, missed question text) is
caught too.

## Running the tests

```fish
set RUST_PATH (cat ~/.cargo/target/.rust-store-path)
env RUSTC_WRAPPER="" PATH="$RUST_PATH/bin:$PATH" cargo -Zscript test --manifest-path ../../claude_sessions.rs
```
