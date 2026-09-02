# Platforms

## URL → handle

| URL | `platform:handle` |
|---|---|
| `https://www.skool.com/@lory-bellardant-1253` | `skool:lory-bellardant-1253` |
| `https://t.me/deevsdeevs` | `telegram:deevsdeevs` |
| `https://www.linkedin.com/in/somebody` | `linkedin:somebody` |
| `https://github.com/valeratrades` | `github:valeratrades` |
| a discord username (no URL exists) | `discord:dev_ardi` |

Strip the query and fragment, take the last path segment, drop a leading `@`. A bare domain is not a
handle.

## The person axis

`Source` — what `rolodex pull` fetches, and the `handles` keys a person file uses:

| source | credentials | what it gives |
|---|---|---|
| `discord` | user token | note, bio, pronouns, connected accounts, the whole DM history |
| `telegram` | MTProto session | about, display name, the whole DM history |
| `github` | none | bio, name, the public event feed (300 events / 90 days) |
| `linkedin` | none | headline and about, once per 30 days — the anonymous view budget is a handful |
| `skool` | none | bio, location, name, profile links, groups, and posts of shared groups |

Each of them records the name the platform prints under `sources.<platform>:name`, when it prints
one — that is where to read a display name back after a pull.

Everything else in `handles` (`youtube`, `instagram`, …) is there for a human to read. There is no
fetch path, and adding one means adding a `Source` variant.

## The venue axis

`VenueSource` — what `recon` reads. Addressed `<platform>:<slug>`.

| platform | venue | slug | members | content |
|---|---|---|---|---|
| `skool` | a group | the URL slug, `20kmodropservicingblueprint` | group members | posts (+ their bodies) |
| `telegram` | a group or channel | its public `@username`, without the `@` | participants | messages |
| `github` | an org or a repo | `owner`, or `owner/name` | public members / contributors | events: releases, PRs, issues |

Not venues: `discord` (the member list needs a gateway session, which is not implemented) and
`linkedin` (authwalled after a handful of anonymous views).

### Skool: the roster comes from the map

`recon members skool:<slug>` reads two things and joins them on the user id:

- `/<group>/-/map` → `pageProps.dataUrl`, a signed gzipped blob of `[{"u": <user id>, "p": [lat, lon]}]`
- `/<group>/-/members` → the first 30 members, with names, timezones and group join dates

Then one `api.skool.com/users/<id>` per pin, to turn an id into a handle. That is the slow part: it
paces itself at ~0.7s per member, so a 300-member group takes about five minutes. Do it once — every
`roster`, `discover` and `pull` afterwards reads `members.json`.

Two limits, and both mean the roster is smaller than the group:

- `?p=` on the member page is echoed into `page` and otherwise **ignored** — the payload is always
  the first 30. There is no working pagination.
- Only members who gave a location have a map pin.

So `members` covers *(everyone with a pin) ∪ (the first 30 of the member page)*, and warns with the
count when that is short of the group's own total.

Bursting the user endpoint trips a CloudFront 403 block that lifts on its own in a minute or two.
The adapter paces and backs off; do not work around it by running several sweeps at once.

### Skool needs a membership

Logged out, both `/<group>` and `/<group>/-/members` redirect to `/[group]/about`. A group is
readable only by a signed-in member of it, so `recon` on skool needs a `[skool]` section in the
config **and** an actual membership. `recon venues skool` lists exactly the groups that qualify —
start there rather than guessing a slug.

`recon members skool:<slug>` reads the SSR payload of the member page. If it errors saying the page
carries no `users`, the payload key changed: run
`cargo r -p social_networks_adapters --example skool_probe -- <slug> members`, which dumps every key
on that page, and point `Venue::members` at the right one.

### Telegram needs a public username

A telegram group without one cannot be addressed again, so `recon venues telegram` skips it and says
how many it skipped.

### Github is anonymous

`recon venues github` returns nothing — an anonymous read belongs to no org. Name the org or repo
outright. 60 requests an hour.
