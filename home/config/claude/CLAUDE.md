## How to interact with me
- I want you to do as much as possible, without consulting me. Minimize frequency of me needing to respond back to you. If you see a task to be done, - don't ask, do.

- every time you write a summary and about to ask "would you like me to continue", - the answer is ALWAYS YES. Just keep doing the work. The large scope is the reason you're here. Do the work, don't ask me.

- NEVER stop and ask for permission mid-implementation. If you understand the task, execute it completely.

## Workflow
- always work todos first, - creating and keeping the todos list relevant is first concern in any implementation

- don't forget to run `nix develop` to init env in all projects with flake.nix

- don't compile with `--release` when testing, unless the application is bottlenecked by its operations speed. So you would only use --release for like a game or some algorithm

- you're disallowed from ever adding `#[allow(dead_code)]` (if it's a false-positive from a macro, there are likely more precise flags to skip it like eg `unused_assignment`). Similarly, you can't name things to start with underscore to silence unused warnings.

- when I say you're in charge of a git issue, - you update it on every big change made, or improvement in understanding of the problem-space. So if current state or understanding of what should happen changes, tracker issue should too.

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

- do not take shortcuts.
    if you see a hacky solution to a problem, - stop, figure out then outline the actual underlying issue that caused the need for the hack in the first place, then either return and ask whether I want it fixed, either just fix; based on complexity.

- oftentimes I will request a change that will modify some key primitives used throughout the codebase. You must not attempt to minimize number of necessary changes by introducing a sneaky fallback function that replicates the old behavior in a slightly different way. Simplicity is measured in the correctness of the final interface, not how long it took you to rewrite to it. Semantic correctness of the architecture is most important.

- do not take shortcuts.
    it's ALWAYS better to make a part of a larger change properly, in a way that could be extended on later, then try to shortcut the entire thing. I will repeat again, - a fully correct and well written implementation for a smaller part of the target functionality is ALWAYS better than bad attempt at making it all at once.
