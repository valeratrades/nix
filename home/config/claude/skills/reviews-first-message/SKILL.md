---
name: reviews-first-message
description: Draft first outreach messages for the top n ranked `reviews` leads into staging, for `release` to move into their outboxes. Trigger on "write first messages for top n reviews leads", "draft outreach for reviews", "/reviews-first-message <n>".
---

# First messages for `reviews` leads

Input: `n`, how many top-ranked leads to draft for. A percentage counts too ("10%" of the people in the purpose).

1. Get the order with `/home/v/s/social_networks/target/debug/social_networks purpose reviews rank`. The first column is the score, the third is the person. Take the first `n`.
2. Pipe those names into `/home/v/s/ev/_service_arb/remote_reviews_automations/target/debug/remote_reviews_automations to-draft /home/v/s/g/rolodex/reviews -s facebook`. It prints only the people who need a draft: no draft yet, or the draft was made from another prompt version or other lead data. It removes their outdated draft, staged or released, and reports on stderr how many it skipped. Draft only the printed people. Build it first with `cargo b` in `nix develop` there if it is missing.
3. Read `/home/v/s/g/rolodex/reviews/<person>/__main__.nix` for `tags.business`, `summary` and `sources`.
4. Write one message to `/home/v/s/g/rolodex/reviews/<person>/drafts/facebook/<at>.md` (staging; never into `outbox/`). `<at>` is the current UTC time rounded up to the minute, as `%Y-%m-%dT%H:%MZ`. The file holds only the message text.
5. After each message is written, run `/home/v/s/ev/_service_arb/remote_reviews_automations/target/debug/remote_reviews_automations drafted /home/v/s/g/rolodex/reviews/<person> -s facebook`. This records the stamp in `<person>/drafts/facebook/stamp`. Without the stamp, the next run stops with an error at this person.

With more than ~20 leads, hand steps 3–5 to a background Opus agent and point it at the notes below.

## Message rules

The source of truth is `/home/v/s/ev/_service_arb/remote_reviews_automations/tmp/campaign_message_generation/`:
- `user_inputs.md`: the user's instructions and critiques, word for word. These win over everything else.
- `understanding.md`: the current distilled rules, and what failed before.
- `refs/`: the reference DMs and their analysis.

Read all three every time; the rules change as critiques come in. Right now (v3) the shape is give, then ask, then joke. That means a personal hook, a genuine offer of value (coding help, or owing them one), the review asked for plainly and shrunk to nothing, and the 1€ only as a joke afterwards. Never plead. Put the bubbles on separate lines with a blank line between them, for `send --multi-message`.

New critiques from the user go into `user_inputs.md` word for word, and then `understanding.md` is rewritten to match. Each rewrite increments the `version: <n>` on its first line. That makes every draft from the old rules due again.

## Then

- The user reads the staged drafts with `/home/v/s/ev/_service_arb/remote_reviews_automations/target/debug/remote_reviews_automations outbox /home/v/s/g/rolodex/reviews -s facebook`.
- Only once the user approves, release them: `/home/v/s/social_networks/target/debug/social_networks purpose reviews rank | sed -n 2,<n+1>p | awk '{print $3}' | /home/v/s/ev/_service_arb/remote_reviews_automations/target/debug/remote_reviews_automations release /home/v/s/g/rolodex/reviews -s facebook`. It moves current-version drafts into `outbox/facebook/`, warns about outdated ones, and first retracts released drafts of another version. `outbox/` is what `purpose reviews send` sends.
- Commit only the staging and outbox files in `/home/v/s/g/rolodex`: `git add -A -- reviews/*/drafts reviews/*/outbox` (unquoted, so the shell expands it; quoted pathspecs fail there), then `git commit --no-verify`. The pre-commit hook there stages the whole repo.
- Sending is the user's call. Run it only when they ask, with the count they give: `cd /home/v/s/social_networks && nix develop -c ./target/debug/social_networks purpose reviews send --multi-message -n <N>`. It sends to the N best-ranked people with a released draft. Run it in the background, since every person takes about a minute.
