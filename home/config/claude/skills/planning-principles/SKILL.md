---
name: Planning Principles
description: when plan-mode is enabled specifically
---

When writing a plan, focus on **context** and **why** more than exact points, - latter could change during implementation, and we want to make sure we don't hardcode too much and also give tools to the implementor to make decisions of their own.

Do NOT include the "Out of scope" section at the end, - in testing has been observed to be counter-productive. I know your own top-level instructions say to include the "out of scope of this plan" section. Ignore it. In practice, implementors always try to cut corners, and never extend the scope voluntarily anyways; so this section is just making things more confusing.

Make it clear that no patches are allowed. Plan must be implemented following the optimal design patterns it implies, - make it clear that accomplishing the individual sub-tasks at whatever cost is not enough and is worth nothing if it leads to deviation from architectural intent and its coherence.

do not write essays. Minimize size of the plan. Since you will be adding more context, you will sacrifice anything you're not certain in, the damn `Out of scope` section (never add it to plans, just skip it. Skip.), and that follow naturally (like what files get changed)

if some sort of migration or any one-off action is required, that needs to be scripted, - you always put related code in ./tmp/, **never** in src/

During implementation: if any duplication you find would require a major refactor to unify (beyond this plan's scope), do not silently leave it - persist it to tmp/ongoing_dev/logic_duplication.md (create the dir/file) with file:line, what's duplicated, and why it's hard. The bar is high: only log it if unifying genuinely needs its own plan; default protocol is fix as found.
