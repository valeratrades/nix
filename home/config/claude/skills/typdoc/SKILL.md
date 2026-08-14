---
name: typdoc
description: "Write a `<name>.typ` design document for a subsystem — a Typst file that draws how the thing works, using fletcher diagrams. Use when asked to {draw up / document / model} a module or subsystem's operation, or to add a .typ next to existing ones. Also covers keeping such a file up-to-date."
---

# typdoc

A `.typ` next to a sub-crate, documenting how that sub-crate operates. Text drawings first,
`fletcher` diagrams under the sections they illustrate, and any section that reports numbers
written as Typst code that recounts them at render.

Worked example, and the file to read before writing a new one:
<https://github.com/EV-invest/trading_data/blob/main/trading_data_dag/model.typ>
(siblings: `trading_data_persistence/weaver.typ`, `trading_data_persistence/book.typ`)

## The order

1. **Seed.** If they already exist, read nearest `.typ` in the repo. It carries the format,
   the register and the preamble, so those need no instruction.
2. **Cover.** `/graphify` over the subsystem before reading by hand. Put this in the body of
   the request; trailing "also remember to" gets dropped.
3. **Text only.** ASCII plates. Every transitional state the data passes through, and the
   reason each decision is made the way it is. Iterate over the plates a few times to narrow
   down on the most explicative model. Nothing else gets written yet.
4. **Then draw.** `@preview/fletcher` once the text has settled. One diagram per section,
   placed directly under the section it illustrates. A trailing gallery of all the diagrams
   loses the pairing.
   the sources and computes at render. See "Counted sections" below.
5. **Iterate.** ensure what you wrote and drew makes sense, read the skills and docs instructions again, polish what you have, focus on removal of excess. While compiling the typ document to see if you drew the graphs correctly, always compile under /tmp, - no garbage artifacts to be added to source.

> if you have sections that report counts / sizes / costs, - anything that will change with time, - you must have it compile procedurally. The `model.typ` from `trading_data` linked above has an example of how it's done, if you need it.

## Register

- Explain what happens. Do not sell it. Whether the design is good is not settled at the time
  the document is written.
- No sensational language, no judgments about the design, no `it's X — not Y` constructions.
- Comments and prose earn their place the same way they do in code: the *why*, not the *what*.

## Counted sections

Prose about how many of something there are goes stale silently. Write it as Typst instead —
walk the module tree from the crate roots and regex-probe, so the table recounts on every
render:

```typst
#let roots = (simple: ("lib", "main"), spl: ("lib", "main"))
#let walk(file, kids) = {
  let src = read(file)
  src.matches(regex("(?m)^\\s*(?:pub\\s+(?:\\([^)]*\\)\\s*)?)?mod\\s+(\\w+)\\s*;"))
     .map(m => m.captures.first())
     .fold(src, (acc, m) => acc + "\n" + walk(kids + m + ".rs", kids + m + "/"))
}
```

Hardcoding the file list is the failure mode this replaces. The section presents what it finds
and explains nothing.

`read()` cannot escape the Typst root, which is the `.typ`'s own directory — symlink in what
sits above it (`trading_data_dag/.examples -> ../examples`).

Numbers that come from running something (benches, replays) get emitted to a small file by the
test/bench run and embedded statically, rather than shelled out to from the document.

## Rendering

No `.pdf` in the repo, ever. Compile to a named pipe under `/tmp`:

```sh
mkfifo /tmp/<name>.pdf 2>/dev/null
typst compile <path>/<name>.typ /tmp/<name>.pdf
```

A write to a fifo blocks until the viewer opens the read end, so run it detached and do not
wait on it. Nothing is checked into the tree.

## Where it sits in the doc hierarchy

`ARCHITECTURE.md` reasons about the whole application's problem space and links to the
per-sub-crate `.typ` for internals. Documentation stays at the precision of the level it sits
at; the same pattern repeats one level down when a sub-crate grows modules worth their own
files.
