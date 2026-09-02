---
name: rolodex
description: "Add somebody to the rolodex, or work out who to reach out to in a community. Triggers on a profile URL (skool.com/@…, t.me/…, linkedin.com/in/…, linkedin.com/company/…, github.com/…, discord), on `platform:handle`, on a name already in the rolodex, on a group/venue URL, and on phrases like \"add to rolodex\", \"pull\", \"who should I reach out to in\", \"who is in\". Runs the `social_networks` binary; never sends a message without explicit confirmation."
---

# /rolodex

The `social_networks` repo keeps a person axis (`rolodex`) and a venue axis (`recon`). This skill
drives both from a URL or a name, and stops before anything leaves the machine.

## Before anything

The repo is `~/s/social_networks` unless the user says otherwise. Commands:

```
cd ~/s/social_networks
nix develop -c cargo r -p social_networks -- rolodex <subcommand>
nix develop -c cargo r -p social_networks_reach --bin recon -- <subcommand>
```

The rolodex directory is `[rolodex] path` in `~/.config/social_networks.nix`. Read it once; every
path below is relative to it.

## Routing

| input | route |
|---|---|
| a profile URL, any platform | → `platform:handle`, then **person** |
| `platform:handle` | **person** |
| a name that already has a file | **person**, skipping creation |
| a venue URL, or `platform:slug` where the slug is a group | **venue** |
| several of any of the above | fan out, one at a time |

`references/platforms.md` has the URL → handle patterns and what a venue means per platform. Read it
when the input is a URL.

## Person path

1. **Find them.** `ls <dir>/*.nix` and grep the files for the handle — a person's file stem is a
   guess, and `handles` is what actually addresses them. Do not create a second file for somebody
   who is already there under another stem.
2. **Write a skeleton** only if nobody matched:
   ```nix
   {
     handles = {
       skool = "lory-bellardant-1253";
     };
     summary = "";
     log = [ ];
     sources = { };
   }
   ```
   The stem is `<first>-<last>` slugged, or the handle when no name is known. You will not know the
   name before the first pull if the URL does not carry one — pull under the handle, read
   `sources.<platform>:name` back out of the file, and `git mv` the pair (`<stem>.nix` and
   `<stem>/`) if it turns out to be somebody with a name. The stem is not load-bearing.
3. **Pull.** `rolodex pull <stem>`.
4. **Report what actually landed.** Read the file back. If the pull returned only a bio and the
   summary is one sentence off it, say exactly that — "skool gave a bio and a location, no posts,
   because we share no group with them" — rather than reporting success. A near-empty file is the
   normal outcome for a stranger on one platform, and calling it a win is the failure mode here.

## Venue path

Confirm reach first: a venue you cannot read fails four commands in a row otherwise.

1. `recon venues <platform>` — the slugs this session can actually see.
2. `recon members <platform>:<slug>` — writes `members.json`.
3. `recon posts <platform>:<slug> --since 90d` — appends the transcript. Idempotent: re-running one
   window writes nothing.
4. `rolodex discover <platform>:<slug> [predicates] --dry-run` — show the selection to the user.
5. Rerun without `--dry-run` once they agree, then `rolodex pull` over what it created.

Predicates: `--active-since <tf>`, `--min-posts <N>`, `--handle-matches <glob>`, `--limit <N>`, and
`--where '<sql>'` for anything else. The columns are in `references/roster.md`. Prefer a `--dry-run`
with a wide predicate over a narrow guess — the roster is a few hundred rows and reading it is free.

## Outreach

Only when the user asks who to contact.

`rolodex cold [pattern]` is the shortlist: everybody whose sources have been read and hold no
conversation. It prints apart, under `?`, anybody whose discord or telegram nobody has pulled yet —
those are unanswered, not cold, and a `pull` is what settles them.

Per person, read their `<stem>.nix` and their lines out of the venue transcript
(`grep '\[<handle>/' <dir>/venues/<platform>/<slug>/*.md`), and draft **one** message. Say what in
their own words it hangs on.

**Nothing is sent without explicit confirmation.** `rolodex dm --<platform> <pattern> <text>` runs
only on text the user has approved, verbatim. `dm` refuses a pattern that matches more or fewer than
one person — that refusal is the safety property, and is never worked around by broadening the
pattern, by looping over matches, or by passing a stem you have not confirmed. If it refuses, show
the matches and ask.

## What not to do

- Do not run `recon` in a loop or over a list of venues unprompted. Every call spends rate limit and
  account standing, which is why no daemon is allowed to call it.
- Do not edit a venue transcript or `members.json` by hand. They are what `recon` wrote.
- Do not paste a secret into a person file. The extraction prompt refuses to; so should you.
