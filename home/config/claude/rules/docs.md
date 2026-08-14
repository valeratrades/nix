---
paths:
  - "**/ARCHITECTURE.md"
  - "**/README.md"
  - "docs/**"
---

all documentation, spec and invariants. Comment rules live in CLAUDE.md, - they must be in context whenever code is written, which a path-scoped rule can't guarantee

## General Rules
- brevity is extremely important. Never write a word if it doesn't add context.

- never defend a decision. Saying why it was taken is fine; arguing that it is correct is not, - it wastes space and makes the decision harder to revisit once we discover we were wrong. No assertive statements, no self-congratulation.

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
the most important file in the repo. Every recurring contributor reads it in full, so every line is paid for many times over, - it must be as small and as informative as it can be. Ruthlessness here is required.

it represents the **correct** architecture and data-flow. If something is misimplemented right now, we write how it should be, not how it is. Code follows ARCHITECTURE.md, never the other way around.

what goes in:
- bird's eye view: the problem the project solves, before any structure
- codemap: high-level module map, answering "where is the thing that does X" and "what does the thing I'm looking at do". A map of a country, not an atlas of maps of its states
- names of the important files, modules and types, - they are the landmarks readers navigate by. No links into code, they decay; a name plus symbol search does not
- boundaries between layers and systems, - they define what implementations are possible inside each
- structural invariants, stated as absences wherever possible (eg "nothing in the model layer depends on views"). Fundamental ones live in [spec](#spec) instead
- cross-cutting concerns, in their own section

what stays out: how a module works inside, anything that changes often, anything that would need re-syncing on every refactor.

revisit a couple of times a year rather than continuously. If the grouping you find yourself describing doesn't match the directory layout, the directories are what should move. //NB: I'm referring to optimal architecture here, not the one outlined in the current document version. Keep in mind that everything can get outdated, and it's on you to figure out if it's the code that's behind the target state outlined in documentation, or documentation is behind the new findings/considerations that have already impacted the code shape.

## Mod Level Docs
each sub-crate or module deserves its own docs section, - `//!` header, or a README.md sitting next to it.

covers:
- what the module owns: the few types and fns a consumer touches, and what they promise
- local conventions the whole module obeys, - a trait everything here implements, naming scheme, error type, doc style
- constraints it imposes on consumers, and those it accepts from below

stays out: anything global (→ [ARCHITECTURE.md]), anything fundamental (→ [spec](#spec)), anything internal (→ the code).

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
