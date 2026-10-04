---
name: reviews-first-message
description: Draft first outreach messages for the top n ranked `reviews` leads into their outboxes. Trigger on "write first messages for top n reviews leads", "draft outreach for reviews", "/reviews-first-message <n>".
---

# First messages for `reviews` leads

Input: `n`, how many top-ranked leads to draft for. A percentage counts too ("10%" of the people in the purpose).

1. Get the order with `/home/v/s/social_networks/target/debug/social_networks purpose reviews rank`. The first column is the score, the third is the person. Take the first `n`.
2. Skip anyone who already has a file in `/home/v/s/g/rolodex/reviews/<person>/outbox/facebook/`.
3. Read `/home/v/s/g/rolodex/reviews/<person>/__main__.nix` for `tags.business`, `summary` and `sources`.
4. Write one message to `/home/v/s/g/rolodex/reviews/<person>/outbox/facebook/<at>.md`. `<at>` is the current UTC time rounded up to the minute, as `%Y-%m-%dT%H:%MZ`. The file holds only the message text.

With more than ~20 leads, hand steps 3–4 to a background Opus agent and point it at the notes below.

## Message rules

The source of truth is `/home/v/s/ev_invest/_service_arb/remote_reviews_automations/tmp/campaign_message_generation/`:
- `user_inputs.md`: the user's instructions and critiques, word for word. These win over everything else.
- `understanding.md`: the current distilled rules, and what failed before.
- `refs/`: the reference DMs and their analysis.

Read all three every time; the rules change as critiques come in. Right now (v3) the shape is give, then ask, then joke. That means a personal hook, a genuine offer of value (coding help, or owing them one), the review asked for plainly and shrunk to nothing, and the 1€ only as a joke afterwards. Never plead. Put the bubbles on separate lines with a blank line between them, for `send --multi-message`.

New critiques from the user go into `user_inputs.md` word for word, and then `understanding.md` is rewritten to match.

## Then

- Commit only the outbox files in `/home/v/s/g/rolodex` with `git add reviews/*/outbox && git commit --no-verify`. The pre-commit hook there stages the whole repo.
- `purpose reviews send` cannot send over facebook yet (`Messenger` has no `Facebook`), so the drafts stay in the outboxes until that exists.
