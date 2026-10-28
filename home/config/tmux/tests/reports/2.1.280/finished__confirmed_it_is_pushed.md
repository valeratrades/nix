<prompt>
is everything merged in, no castaway prs or whatever?
</prompt>

Yes. All my work was committed straight to `main` and pushed in both repos; no PRs were opened, and neither repo has an open PR or an extra worktree.

```
emulate_phone_cam  origin/main = 9b57611   5a4d77d  bb1b60b  c15f681  9b57611
emulate_android    origin/main = 75f7518   fc69880  d180865  75f7518
```

phone_cam does have uncommitted changes, but they aren't mine: `tools/gologin/src/cdp.rs`, `facing.js`, `accounts/_devices/captures/`, and edits to `oracle.html`, `main.rs` and the nix files. A second agent is active on this repo (`active_agents` = 2), so I've left them alone.
