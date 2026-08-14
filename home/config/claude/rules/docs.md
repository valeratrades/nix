---
paths:
  - "docs/**"
  - "**/*.typ"
  - "**/README.md"
---

all things documentation, Spec and Invariants

everything we write is there for a single purpose: **giving programmer context** **necessary** for making correct **decisions when editing**.
Absolutely everything else follows suit from this.

## General Rules
- brevity is extremely important.
  Never write a word if it doesn't add context.

- never defend a decision.
  Saying why it was taken is fine; arguing that it is correct is not, - it wastes space and makes the decision harder to revisit once we discover we were wrong. No assertive statements, no self-congratulation.

- legacy parts of the implementation are to never be mentioned.
  The only place where it's acceptable is CHANGELOG.md. When we realize that some part of what we're doing is wrong, - we start treating it as it never existed, we do not document things like "unlike the old design, we do X". Documentation is about what happens at lower level, and why (and under what constraints) it happens at the higher level; - there is no space for anything else.

- documentation must be placed as close as possible to the point of its **utilization**.
  Meaning, if we want to talk about why some trait looks as it does, - it goes onto the trait as doc-string. If we talk about how some objects from different parts of a module interact, - it goes onto the doc of the module. If we're talking about boundary of a sub-crate, it goes on sub-crate level doc. If we reason about what parts of the problem space the sub-crates cover, and thus what thin waists between them are appropriate, - this goes in top-level architecture.
  This achieves two objectives: 1) closer it is to the thing it covers, the more difficult it is to get outdated; 2) the reader only sees it when they get down to the level where knowing and reasoning about the objects it covers is necessary.

- don't restate details.
  If same piece of information (which isn't an Invariant/Spec), is restated in different places, - this is no better than code duplication. It should be brought up to the level it becomes relevant at, and then just referenced.

- drawing > speaking
  as always, when something can be shown more concisely through drawing, it should be. Back to brevity, - we use the medium that captures the concept most precisely, thus saving the reader from having to ingest more "information tokens" than necessary. Great example is cross-section relationships, - a single drawing at the top will save a lot of hand-waving in text.

- don't mention things that are already managed automatically.
  Documents are there for the developer to know how to reason about the problem space, before diving into making edits. So think about it: if some property is already enforced through type system, we don't need to mention the need to provide it. Code is the best documentation.
  To give an example of when docs are necessary, through the same lense, - consider what if we had a magical rust-flag to say "force zero-cost", - we wouldn't need to add this as an Invariant, would we. And then it's absence is what makes us have it listed. Documentation that stays is **documentation we can't remove**.

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
the most important file in the repo is [docs/ARCHITECTURE.md]. Every recurring contributor reads it in full, so every line is paid for many times over, - it must be as small and as informative as it can be. Ruthlessness here is required.

it represents the **correct** architecture and data-flow. If something is misimplemented right now, we write how it should be, not how it is. Code follows ARCHITECTURE.md, never the other way around.

what goes in:
- bird's eye view: the problem the project solves, before any structure

- high-level invariant directionality
  Think of it as reasoning behind invariants. The formulated rules around them then are recorded inside [spec](#spec).
  So we can reason that we desire the trading execution project to be zero-cost. From this then, we end up deducing trade-offs that influence decisions, - for example, that no amount of cost saving during backtests can justify tiniest performance degradation in live runs. That then is recorded inside the spec.

- codemap: high-level module map, answering "where is the thing that does X" and "what does the thing I'm looking at do". A map of a country, not an atlas of maps of its states
- boundaries between layers and systems, - they define what implementations are possible inside each
- cross-cutting concerns, in their own section

what stays out: how a module works inside, anything that changes often, anything that would need re-syncing on refactors.

revisit a couple of times a year rather than continuously. If the optimal grouping you find yourself describing doesn't match the directory layout, the directories are what should move.

> Note that we're not that far from [mod-level docs](#mod-level-docs) here. They too stand to represent the architecture of the considered scope. It's all about the level we're reasoning about the implementation at.

## Mod Level Docs
many sub-crates or modules deserve their own docs section, - we do this through a README.md sitting at its root.
It is then embedded into doc-string of its `mod.rs` using `#![doc = include_str!("README.md")]`, (or into sub-crate's top-level `lib.rs` with `#![doc = include_str!("../README.md")]` from `src/` above it)

covers:
- what the module owns: the few types and fns a consumer touches, and what they promise
- local conventions the whole module obeys, - a trait everything here implements, naming scheme, error types, - anything specific to us.
- constraints it imposes on consumers, and those it accepts from below

stays out: anything global (→ [ARCHITECTURE.md]), anything fundamental (→ [spec](#spec)), anything internal (→ the code).

> be always very cognisant of entropy, - every line and word will have to be maintained manually. Every single word here is a cost, - a trade-off between allowing people to reason about code inside the sub-crate/module at a glance vs ending up confusing them with outdated references/explanations down the line.

and again, note how similar this is to top-level ARCHITECTURE.md. The lower we go, the less consistent the shapes will be, so it has more freedom. But underlying idea is all the same, - presenting the core of the relevant considerations at the level where their understanding becomes necessary.

### In-Depth Logic
in large projects, we will often have non-trivial systems introduced to solve the underlying problem. They can be very complex and difficult to wrap the head around. For them, we write a specialized Typst document, to give a handle on reasoning about them.

for how to write them, refer to [`/typdoc` skill](../skills/typdoc)

## Spec
spec is a concept we add for procedurally keeping track of Invariants.

> as it concerns Invariants, it is one of the defining points of the project, - all changes to it are to be subject to utmost scrutiny, and to be reported to me separately.

it is NOT for describing current state of the project or primitives in it. Only part that it should cover, is the fundamental considerations, based on which the decisions to be made.
Once again, - fundamental, - not those caused by current project arch: this is THE place to talk about us promising to keep some part of the architecture zero-cost for example; but it is NOT the place to say that some trait needs to be implemented by everyone, or that some particular style of documentation is to be used for a group of objects, - those are concerns to be outlined at [mod's level](#mod-level-docs)

### Tracey
`tracey` cli is attached to help with tracking these invariants, but procedural enforcement it allows for is narrow, - we have to be vigilant ourselves in upkeeping it

you have a [`/tracey` skill for using it](../skills/tracey/). What is even more important though, is why/when to:
1. only declare requirements that can't be forced programmatically. No amount of reminders can compare with being fundamentally forced to do something.
2. each requirement has a level at which it is relevant. Important ones will live in top-level [docs/spec/], as mentioned in [Architecture section](#architecturemd), but in complex workspaces we may need to enforce per sub-crate or even per-module invariants: those trivially then need to reference `spec/` declared at the same level.
3. be mindful of adding new requirements. Each will shape all the code in the section it impacts, so we can only afford to add those that follow from first principles. Each is required to be kept in mind at all times, so we can't waste them on minute details.
4. each rule must follow from first principles, so their descriptions are naturally concise. If while reading the spec, you notice that a rule has multiple paragraphs on it, - it's very likely invalid: having to explain so much means it carries a lot of internal implementation state. And if you notice that you wrote a verbose rule yourself, - stop and consider whether you can abort its addition.

> for a good rule of thumb, - ask "does the rule require to be kept in the head when editing". If not, drop it.

  Example: say we had a rule that required objects implementing a weaker version of some trait, to say why they can't use the stronger one. If that trait then gets `const WHY: &'static str;` on it, - this will make compiler force the programmer to add it. The text rule then stops adding anything, and is to be removed.

## Upkeep
regardless of what you are working on atm, all violations you find in docs (or of code against docs) are to be noted, and either fixed in-place (do yourself if other rules here cover what to do with it), either brought up to me in the end (if you found a fundamental error, and there is no straight fix that wouldn't have deep implications).

the core spec surface must be lean, and following [outlined rules](#spec). If possibility of (making Spec and Invariants more concise and focused), or (decoupling it from accidental dependence on current code's shape), etc, are found, - they are worthy of being added to your implementation's todo list immediately. Note however, that we are not to change the meaning of the spec lightly, - Invariants are above code, and if it seems that you found some that are wrong/unworthy of being invariants, - you are to suggest a fix for them to me, at the end of your work.

> because of how important Invariants are to the shaping of the entire codebase, polishing them is worthwhile
