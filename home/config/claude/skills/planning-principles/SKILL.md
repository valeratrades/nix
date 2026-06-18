---
name: Planning Principles
description: when plan-mode is enabled specifically
---

When writing a plan, focus on **context** and **why** more than exact points, - latter could change during implementation, and we want to make sure we don't hardcode too much and also give tools to the implementor to make decisions of their own.

Do NOT include the "Out of scope" section at the end, - in testing has been observed to be counter-productive. I know your own top-level instructions say to include the "out of scope of this plan" section. Ignore it. In practice, implementors always try to cut corners, and never extend the scope voluntarily anyways; so this section is just making things more confusing.

Make it clear that no patches are allowed. Plan must be implemented following the optimal design patterns it implies, - make it clear that accomplishing the individual sub-tasks at whatever cost is not enough and is worth nothing if it leads to deviation from architectural intent and its coherence.

do not write essays. Minimize size of the plan. Since you will be adding more context, you will sacrifice anything you're not certain in, the damn `Out of scope` section (never add it to plans, just skip it. Skip.), and that follow naturally (like what files get changed)

if some sort of migration or any one-off action is required, that needs to be scripted, - you always put related code in ./tmp/, **never** in src/

during implementation: if any duplication you find would require a major refactor to unify (beyond this plan's scope), do not silently leave it - persist it to tmp/ongoing_dev/logic_duplication.md (create the dir/file) with file:line, what's duplicated, and why it's hard. The bar is high: only log it if unifying genuinely needs its own plan; default protocol is fix as found.

every single question you ask me is a HUGE cost. It is MUCH cheaper for me to analyze the ready implementation once the plan has been thought through by you, and properly compiled. You ONLY ask questions if you can't resolve them yourself based on the principles outlined in CLAUDE.md. Your work is much more valuable if you get there on your own, without needing me to baby-sit you and answer questions.

when you have wrote the plan, I don't want you to immediately present it. Once the plan is ready and you think it's good for submission (fully written out already), - I need you to go into the final review phase, and narrow down on problems and inefficiencies with suggested approach, potentially simplifying/fixing it; maybe discovering other potential bugs, - everything that can go wrong, or can be fixed before we lock the arch.

before using the interface to submit me the plan for acceptance, - imagine that you already did, and I'm asking you "Is this the best that you can do?". If the answer is not certain, - you come back and you work on it further.
