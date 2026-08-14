# Source prompts
<!--added to showcase what kinds of problems appeared in naive approach, - to ensure that our harness covers all of them-->

Verbatim, from the sessions that produced
<https://github.com/EV-invest/trading_data/blob/main/trading_data_dag/model.typ>,
`trading_data_persistence/weaver.typ` and `trading_data_persistence/book.typ` (2026-08-03/04).

## Opening a document

```
in model.typ, draw up the current utilization framework for our DAG primitives. You will
first draw it in text. Also remember to use /graphify for increasing coverage of your
knowledge.
And then, only once you've gotten a text drawing, you will use fletcher lib like
https://typst.app/project/prgiNWvUa5lYrtSnKn28Fp
```

```
read /home/v/s/ev_invest/trading_data/trading_data_dag/model.typ

then study how Weaver operates in /home/v/s/ev_invest/trading_data/trading_data_persistence/,
and compile `weaver.typ`, - draw up its operation, including all the transitional data states
and reasons for decisions. Draw it up in text first, do few iterations over to narrow down on
the most explicative model, and then diagrams come at the very end. Focus on getting the
underlying problem space right, - because all code is fluid around it
```

```
too much text, draw. For each primitive I want their actual shape, and then how they interact
with data. Shape is rust code, interactions are text diagrams
```

```
this is great, read weaver.typ and model.typ documents. And then I want your info persisted as
book.typ in _persistence sub-crate
```

## Layout

```
ok, let's have each graph drawn go under the section it's illustrating
```

## Numbers

```
I absolutely hate /home/v/s/ev_invest/trading_data/trading_data_dag/model.typ:402 section. But
it could be great, - remove all the opinions about the numbers from it, and switch it fully to
just code that would procedurally pull the actual utilization numbers from `examples`. It
shouldn't explain shit, just know to present the data it finds
```

```
amazing. Now I don't like us hardcoding files for each source, - that can easily get out of
sync. Can it just search over all .rs files in there or sth?
```

## Register

```
now remove all the sensational language. Have it just explain what happens, never sell it. I
don't even know if it's a good design yet. No "it's x, — not y" bullshit, none at all is
allowed. I throw up a little every time I see it
```

```
yeah, fuck those judgments too
```

## Artifacts

```
where is model.pdf. Find and delete it. And never compile typst locally again
```

## Placement in the doc hierarchy

```
update ARCHITECTURE.md to reason about _dag and _persistence parts of our codebase in more
abstract terms, and just link to weaver.typ and model.typ for their internals. Idea is to keep
the documentation at precision associated with the level it's positioned at, - ie
ARCHITECTURE.md reasons about the general problem-space of the whole application, and how we
approach it, and then references per-subcrate files for technical details (and then later on if
we have more code and nesting levels, same pattern would repeat with those sub-crates
referencing documents inside their own modules, operating at the primitives present there,
while themselves covering only the top level). // for now only two subcrates have those
specialized files, so if ARCHITECTURE.md already reasons about technical details of those, it's
fine for now and can be kept
```

## Notes on the loop, from what needed re-issuing

- `/graphify` was skipped both times it appeared as a trailing "also remember to".
- The first draft parked all diagrams in a trailing `== 3. The same thing, drawn` section.
- The first census hardcoded a per-crate file list.
- `read()` could not reach `../examples`; resolved with a `.examples` symlink beside the `.typ`.
- Sales register showed up in every draft and needed stripping twice per document.
