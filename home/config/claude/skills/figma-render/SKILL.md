---
name: figma-render
description: "Render a site's current pages into Figma as editable auto-layout frames, every page at every breakpoint, from the repo's own e2e harness (`nix run .#figma`). Use when asked to put/drop/dump/render/push the site, landing or its pages into Figma, to get a Figma snapshot of what the code renders now, or to lay out all breakpoints side by side in Figma for rearranging by hand."
license: "BlueOak-1.0.0"
compatibility: "Figma MCP (generate_figma_design, use_figma, create_new_file); a repo whose flake has `apps.figma` over `@evinvest/figma-render` (sites_tools' mkLanding, site_conductor)"
metadata:
  version: "0.2.0"
---

# figma-render

Figma here is a debug artifact, like a flamegraph: code stays the source of truth, nothing is read back. The
frames come from the repo's Playwright harness (same pinned Chromium, viewports, A/B control cookies and
settle as its screenshot baselines), which serializes each page into Figma through `generate_figma_design`'s
capture script. `html_to_figma` re-renders on Figma's side and would lose the viewports, so it is not an
alternative.

The repo side is the contract, run from the repo root:

- `nix run .#figma -- frames` prints `{ "file": <fileKey> | null, "frames": ["<project> <page>", …] }`.
- `FIGMA_CAPTURES='{"<key>": {"captureId": …, "endpoint": …}, …}' nix run .#figma` builds the site and
  captures exactly the keys given. A key not in `frames` matches no test and is never captured.

Both are `evinvest-figma-render`, the bin of `@evinvest/figma-render` (EV-Main/web_std `ts/figma-render`,
`~/s/ev/web_std`), over the repo's `defineFigmaSuite` specs. Landings wrap it in sites_tools'
`@evinvest/sites-tools/testing/e2e` and `nix/mk-landing.nix` (`~/s/ev/_sa/sites/tools`); site_conductor in
`frontend/tests/e2e` and its flake. Read those when the repo side misbehaves. The Figma steps below stay with
the agent: Figma's MCP registers only allowlisted OAuth clients, so the bin cannot call it.

## The loop

1. `frames`. If `file` is null, the repo has no render board yet: load `figma-create-new-file`, create a design
   file `<pname> — renders` (separate from the brand's design file, which stays hand-made) in the plan the
   other render boards live in ("EV Invest's team"), then set `figmaFile = "<key>";` in the repo's flake
   (`mkLanding`'s argument, or the `figmaFile` binding) and commit it.
2. `create_session` on the file.
3. `use_figma` (load `figma-use` first): create a page named `<git rev-parse --short HEAD> <YYYY-MM-DD>`, with
   ` dirty` appended when `git status --porcelain` is non-empty, since the render is of the working tree.
   Keep its id. A file `create_new_file` just made has one empty page: rename that one instead.
4. `generate_figma_design(fileKey, nodeId = <page id>)` once per frame key, all with one fresh `promptId`.
   Each answer carries a `captureForDesign({ captureId, endpoint, … })` snippet: take `captureId` and
   `endpoint` from it verbatim. Ids are single-use; issue them all before the run, never reuse one.
5. Run `FIGMA_CAPTURES=… nix run .#figma` in the background. The build is most of its time; each capture takes
   seconds once its test starts.
6. Once the run exits, poll each id with `generate_figma_design(fileKey, captureId)`: it answers the frame's
   node id. A test passes only after Figma accepted its capture, so a pending id is a test that failed or was
   skipped, and the run log says which. A failed capture needs a new id; re-run with only those keys.
7. `use_figma`: name each frame by its key, and lay the frames out as a grid, one row per page in `frames`
   order and one column per project, columns as wide as their widest frame plus a gap. Frames arrive named by
   the page's `<title>`, which desktop and mobile share; the poll's node ids are the only mapping.
8. Print the page link: `https://www.figma.com/design/<fileKey>?node-id=<page id, ":" as "-">`.
