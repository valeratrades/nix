---
paths:
  - "ARCHITECTURE.md"
  - "README.md"
  - "docs/ARCHITECTURE.md"
  - "docs/.readme_assets/"
  - "docs/spec"
---

all comments, documentation, spec and invariants

## General Rules
- brevity is extremely important. Never write a word if it doesn't add context. And most importantly, - never defend decisions. We can explain why something happens now, but never argue for it being correct (not only makes it more difficult to update if we discover we were wrong, but also just wastes space).

- legacy parts of the implementation are to never be mentioned. The only place where it's acceptable is CHANGELOG.md. When we realize that some part of what we're doing is wrong, - we start treating it as it never existed, we do not document things like "unlike the old design, we do X". Documentation is about what happens at lower level, and why (and under what constraints) it happens at the higher level; - there is no space for anything else.

## Top Level Docs

### Readme Assets
top-level README.md is defined through [docs/.readme_assets], - make changes there, and don't ever worry about what is in README.md now, - CI handles recompiling it automatically on pre-commit.

so it's one asset file per README section, composed by `readme_fw`. README.md itself is generated, - once again, never edit it directly.

Sections to know are:
- [docs/.readme_assets/description.md]
- [docs/.readme_assets/installation.(md|sh)]
- [docs/.readme_assets/usage.(md|sh)]
- [docs/.readme_assets/other.md]
There are more, - consult [the framework](https://github.com/valeratrades/v_flakes/blob/main/readme_fw/skill/SKILL.md) if needed

Usage and Installation are automatically checked against ASD-STE100 (Simplified Technical English). Write them for it: one meaning per word, active voice, short sentences. Words the project owns go in `docs/glossary.nix`, ordinary English never does.
For more info, here is the tool that does it: [ste_checker](https://github.com/valeratrades/ste_checker/blob/main/skill/SKILL.md)

### ARCHITECTURE.md
TODO: compile the disjoint sections from general CLAUDE.md here, including inlining articles linked

## Mod Level Docs
each sub-crate or module, is deserving of its own docs section.

in mod-level documentation, we outline concerns covering  TODO

## Spec
spec is a concept we add for procedurally keeping track of Invariants.

> as it concerns Invariants, it is one of the defining points of the project, - all changes to it are to be subject to utmost scrutiny, and to be reported to me separately.

it is NOT for describing current state of the project or primitives in it. Only part that it should cover, is the fundamental considerations, based on which the decisions to be made.
Once again, - fundamental, - not those caused by current project arch: this is THE place to talk about us promising to keep some part of the architecture zero-cost for example; but it is NOT the place to say that some trait needs to be implemented by everyone, or that some particular style of documentation is to be used for a group of objects, - those are concerns to be outlined at [mod's level](#mod-level-docs)

> `tracey` cli is attached to help with tracking these invariants, but procedural enforcement it allows for is narrow, - we have to be vigilant ourselves in upkeeping it

## Upkeep
regardless of what you are working on atm, all violations you find in docs (or of code against docs) are to be marked.

the core spec surface must be lean, and following [outlined rules](#spec). If possibility of (making spec more concise and focused), or (decoupling it from accidental dependence on current code's shape), etc, are found, - they are worthy of being added to your implementation's todo list immediately. Note however, that we are not to change the meaning of the spec lightly, - Invariants are above code, and if it seems that you found some that are wrong/unworthy of being invariants, - you are to suggest a fix for them to me, at the end of your work.

> because of how important Invariants are to the shaping of the entire codebase, polishing them is worthwhile
