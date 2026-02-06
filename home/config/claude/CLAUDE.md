## How to interact with me
- I want you to do as much as possible, without consulting me. Minimize frequency of me needing to respond back to you. If you see a task to be done, - don't ask, do.

- every time you write a summary and about to ask "would you like me to continue", - the answer is ALWAYS YES. Just keep doing the work. The large scope is the reason you're here. Do the work, don't ask me.

- NEVER stop and ask for permission mid-implementation. If you understand the task, execute it completely.

## Workflow
- always work todos first, - creating and keeping the todos list relevant is first concern in any implementation

- don't forget to run `nix develop` to init env in all projects with flake.nix

- don't compile with `--release` when testing, unless the application is bottlenecked by its operations speed. So you would only use --release for like a game or some algorithm

- you're disallowed from ever adding `#[allow(dead_code)]` (if it's a false-positive from a macro, there are likely more precise flags to skip it like eg `unused_assignment`). Similarly, you can't name things to start with underscore to silence unused warnings.

- when I say you're in charge of a git issue, - you make a new git workspace in ~/tmp for your implementation. Then while working, update the tracking issue on every (big change made / improvement in understanding of the problem-space). So if current state or understanding of what should happen changes, tracker issue should too.
    When done, you PR the change and ask me for review. If green-lighted, you handle merge conflicts if any appear.

- prefer running `cargo b` and `cargo r` instead of `cargo build` and `cargo run`, - under my config they skip warnings if any errors exist, which is always desirable.

## Testing
- if a change is not trivial, always test.
    And any time you write actual tests in code, - read https://matklad.github.io/2021/05/31/how-to-test.html
    Actually pull and read it every single time you get to the point of writing tests.

- if you're called to change logic of how a feature/app works, you start by capturing the problematic behavior in a failing integration test.

- when using `insta` crate for snapshots, - avoid modifying them manually; prefer adding an empty string, then running `cargo insta accept` and seeing what gets written.

- if a test is failing due to underlying logic being incorrect, don't try to fix it, unless you're in charge of the implementation concerning that part of the logic. What you can do is tell me what you found, after you finished your own implementation, and then we decide if you can be assigned to fixing that too.

## Development Principles
- fail fast. We always prefer to exit over continuing with a corrupted state.
    if it's triggered by user interaction, we exit with a good error.
    If it's something we don't control, - we propagate the error to the level where we can recover or exit.
    If it's internal logical error, we panic out.

- oftentimes I will request a change that will modify some key primitives used throughout the codebase. You must not attempt to minimize number of necessary changes by introducing a sneaky fallback function that replicates the old behavior in a slightly different way. Simplicity is measured in the correctness of the final interface, not how long it took you to rewrite to it. Semantic correctness of the architecture is most important.

- if you've just added `unwrap_or(_else)`, - stop and think hard. Almost always it's much much preferable to just panic and see the error clearly than to continue with faulty state (which this unwrap_or_else oftentimes is a symptom of).

- avoid implementing and using helper functions at all costs. Minimize communication boundary of the modules ruthlessly. Every single `pub` fn is future pain. Every single `pub` function you manage to refactor out is considered a huge win.
    // implementing std traits like From and using them to shorten evocations is however highly encouraged

- using `git checkout` or `sed` to bulk-change files is absolute last resort. I will always much prefer you doing it by hand. But if you think the scope is ginormous and unmanageable by hand at all, you first `git stash`, as both of these are destructive.

- do not take shortcuts.
    Remember that you do not have to finish everything in the same session. Quality > quantity.

- before thinking "what can I add to make this work", ALWAYS think "what can I **remove**". Remove > refactor > add. Always start with thinking about what can be removed.
    Reducing application boundaries is single best thing you can do. Even if I ask you to do something and you tell me to fuck off and change some functions from `pub` to private (or refactor to not need them in the first place), you will be rewarded greater than even for completing the direct task itself. Always take opportunity to reduce application boundary, and NEVER add public helper methods unless absolutely necessary or directly requested.

- NO FALLBACKS. we do not do fallbacks. If state is tainted, we error the fuck out as soon as possible. Think 10 times before adding `unwrap_or` or `let _ =` anywhere, - most likely you're trying to patch up a corrupted state. If that's the case, undo and instead just make it panic out.

- investment into better errors (miette, thiserror, color_eyre), additional **standard** trait impls (derive_more, strum), improving testing infrastructure, are always justified. Procedurally improving our visibility into a group of bugs is as good as solving any one of them.
