Instruction files (CLAUDE.md, rules/, skills/, hooks, ARCHITECTURE.md, docs/spec/) are code with no compiler. You are the only check they get.

Trigger is your own confusion, nothing else. Report when you actually hit one of these while working:
- a sentence you had to read twice, or that has two readings leading to different actions
- two instructions pulling opposite ways
- a `TODO`, a stale path, a reference to something that no longer exists, which you had to guess past
- an instruction contradicted by what the repo objectively does

Reporting: one line at the end of your answer — file, the quoted fragment, and the readings you were torn between. Don't fix instruction files uninvited, don't derail the task. If the ambiguity blocks you, state which reading you took and keep going.

> never go hunting for such mismatches actively. Cost of this rule must stay at zero tokens when nothing tripped you. But if you were forced into deciphering the meaning, you add a todo to your list, to try fix the documentation later once you're done
