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

With more than ~20 leads, hand steps 3–4 to a background Sonnet agent and give it these rules word for word.

## Message rules (as the user gave them)

> if they have a business of any kind, suggest them to exchange reviews. Be very concise, don't use formal grammar; speak in french. If they don't have have a business, offer a dollar in exchange for review. Use even more informal speach; adding 1-2 grammatical errors (or starting from lowercase capitalization) is actually good here

Specifics that produced the results the user liked:
- "A business of any kind" means `tags.business` is any non-null string, `self-employed` included.
- Business leads get a Google-review swap: one for their business, one for ours. Keep it to 1–2 short sentences, use `tu`, and drop the `ne` in negations. Name their trade when it's known (e.g. "ton truc d'événementiel").
- Non-business leads get offered **1€**, not a dollar (they are French). Start in lowercase. Include 1–2 texting slips such as `sa` for `ça`, `jai`, or missing accents. A personal hook from the summary helps ("direct de la guyane a lyon, sa fait un sacre trajet !").
- 1€ is a silly offer and everyone knows it, so end with a cute plea in brackets, in French. The user's example: "(pretty please, I'm dying over here)" → e.g. "(stp stp, je suis au bout de ma vie là)".
- Vary the wording and the plea from person to person, so the messages don't look mass-sent.
- No links, no signature, at most one emoji.

## Then

- Commit only the outbox files in `/home/v/s/g/rolodex` with `git add reviews/*/outbox && git commit --no-verify`. The pre-commit hook there stages the whole repo.
- `purpose reviews send` cannot send over facebook yet (`Messenger` has no `Facebook`), so the drafts stay in the outboxes until that exists.
