# The roster table

`rolodex discover` and `recon roster --where` evaluate a SQL `WHERE` clause against an in-memory
table built from `members.json` joined against the venue transcript. Nothing is persisted; the table
is rebuilt on every call from the markdown, which is the store.

| column | type | notes |
|---|---|---|
| `handle` | TEXT | the platform handle, and the primary key |
| `display` | TEXT | the name the platform prints; the handle when it prints nothing else |
| `joined` | TEXT | RFC3339, or NULL when the platform does not state one |
| `posts` | INTEGER | lines in the transcript attributed to this handle |
| `first_post` | TEXT | RFC3339, NULL when `posts` is 0 |
| `last_post` | TEXT | RFC3339, NULL when `posts` is 0 |

Dates are RFC3339 text, which sqlite compares lexicographically in the same order it compares them
chronologically — `last_post >= '2026-01-01'` works.

`posts` counts only what `recon posts` has actually fetched. A member with `posts = 0` may simply be
outside the `--since` window used, not silent.

## Flags, and what they desugar to

| flag | clause |
|---|---|
| `--active-since 90d` | `last_post >= '<now - 90d>'` |
| `--min-posts 2` | `posts >= 2` |
| `--handle-matches '*-fr'` | `handle GLOB '*-fr'` |
| `--where '<sql>'` | verbatim |

They are ANDed. No predicate at all is the whole roster. `--where` also accepts a path to a `.sql`
file, told apart by asking the filesystem whether the argument names one — use that for anything
worth an editor.

`GLOB` rather than a regex: sqlite ships no `REGEXP` and this build registers none. `LIKE`, `GLOB`
and the rest of sqlite's string functions are all available through `--where`.

## Examples

```sql
-- people who showed up recently and said something
posts > 0 AND last_post >= '2026-06-01'

-- long-standing members who have gone quiet
joined < '2025-01-01' AND (last_post IS NULL OR last_post < '2026-01-01')

-- the loudest twenty
posts >= (SELECT AVG(posts) * 3 FROM members)
```
