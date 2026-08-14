---
name: wrap_for_llm
description: "Ship an agent-facing skill from inside a repo, so an agent in a *downstream* repo can build against it without reading the tree. Use when asked to write/update a repo's own skill, `docs/skill/`, a SKILL.md for a library or framework, or to make a project consumable by Claude Code / Codex."
---

# wrap_for_llm

A repo that others build against ships `docs/skill/` — one `SKILL.md` plus `references/` it links.
It is a **router, not a summary**: it says which file in the repo answers a given question, and
supplies only the mechanical shape the prose there leaves implicit.

Worked example to read before writing a new one:
<https://github.com/EV-invest/trading_data/tree/main/docs/skill>

The rest of the repo's documentation is unaffected — a skill is a wrapper over docs that already
exist, never a place to put documentation that belongs next to what it covers.

## One payload, two agents

Claude Code and Codex CLI both read a directory whose `SKILL.md` opens with `---`-delimited YAML
frontmatter carrying `name` and `description`. Neither reads anything the other rejects, so there
is no per-agent `src/`, no generation step, no packaging. Only the install path differs.

| agent | user scope | project scope |
|---|---|---|
| Claude Code | `~/.claude/skills/<name>/` | `<project>/.claude/skills/<name>/` |
| Codex CLI | `${CODEX_HOME:-~/.codex}/skills/<name>/` | `<project>/.agents/skills/<name>/` |

The installed directory name must equal the frontmatter `name`, which is why the in-repo directory
is `docs/skill/` but the symlink is not. Codex also accepts a `SKILL.json` whose
`interface.short_description` supersedes the frontmatter one — forking the payload for one field, so
do not.

Ship `docs/skill/install.sh`, executable, verbatim:

```sh
#!/usr/bin/env sh
# Symlinks this directory in as the `<name>` skill.
#
#   ./install.sh              → ~/.claude/skills/  and  ${CODEX_HOME:-~/.codex}/skills/
#   ./install.sh <project>    → <project>/.claude/skills/  and  <project>/.agents/skills/
set -eu

src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
name=<name>

if [ $# -gt 0 ]; then
	proj=$(CDPATH= cd -- "$1" && pwd)
	dirs="$proj/.claude/skills $proj/.agents/skills"
else
	dirs="$HOME/.claude/skills ${CODEX_HOME:-$HOME/.codex}/skills"
fi

for d in $dirs; do
	link="$d/$name"
	if [ -e "$link" ] && [ ! -L "$link" ]; then
		echo "$link exists and is not a symlink — refusing to touch it" >&2
		exit 1
	fi
	mkdir -p "$d"
	rm -f "$link"
	ln -s "$src" "$link"
	echo "$link -> $src"
done
```

## Paths resolve against a stated base

Installed, the directory sits outside the repo, so `../ARCHITECTURE.md` resolves to nothing. State
the base once, ordered cheapest first, then write every repo path against it:

1. a local checkout, found mechanically — e.g. `cargo metadata --format-version 1 | jq -r
   '.packages[]|select(.name=="<crate>").manifest_path'`, then the directory above it;
2. `https://github.com/<org>/<repo>/blob/main/<path>` (raw: `raw.githubusercontent.com/…/main/…`).

Links *within* `docs/skill/` stay relative — the tree moves as a unit.

## Sections

In order. Drop any that would be empty rather than padding it.

1. **Hook** — three sentences on what the thing is, in its own vocabulary. Then the one boundary a
   consumer breaks first, with the spec id that forbids it.
2. **Resolve the sources first** — the base above, then the table. This is the primary artifact:

   | path | what it is | read it |
   |---|---|---|
   | `docs/ARCHITECTURE.md` | the claim everything rests on | **always, first** |
   | `<crate>/model.typ` | the mechanism | **before writing a node** |
   | `docs/spec/` | the normative requirements | before trading anything off |
   | `src/lib.rs` | the entire public vocabulary | when an import will not resolve |
   | `examples/simple/` | the fastest complete reading | first contact |

   The third column is what makes it a router. A path with no distinct trigger does not belong.
   Close the section: *nothing in this skill restates those.*
3. **What you actually author** — the smallest complete declaration that compiles, commented. State
   what is derived and therefore absent from it.
4. **The loop** — numbered, each step ending in a `references/` link. Last step is the build:
   whatever the project enforces mechanically is checked there, not by reading.
5. **Rules that get broken** — each enforced already; listed because knowing it first saves a
   rewrite. One bold clause, two lines of why, the spec id in parentheses.
6. **References** — table of `references/*.md` and what each covers. Loaded on demand; the entry
   point stays short.
7. **Verify** — commands that actually run, from the workspace root. Close with the project's kind
   (app / helper lib / framework) and the judgement that follows from it.

## Register

- `description` decides whether the skill ever fires. Enumerate the literal identifiers a consumer
  types — macro names, trait names, type names — not a topic.
- Cite ids and paths, never restate prose. A moved path or a deleted `r[…]` id breaks loudly; a
  paraphrase rots silently.
- Explain what happens, do not sell it. No `it's X — not Y`, no judgement on the design.
- Prohibitions carry their mechanism (`a closed gate pulls no deps, so …`). A rule without one gets
  reasoned around.
- Reach for `references/` when a section outgrows a screen, not before.

## Verify

```sh
docs/skill/install.sh ../scratch-consumer   # both project scopes
```

Then, in a repo that has never seen the source tree: ask for the task the skill exists for. What the
agent gets wrong is what the skill owes, and every path it fails to resolve is a base that was
stated wrong.
