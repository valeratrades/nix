---
name: figma-render
description: "Render a site's current pages into Figma as editable auto-layout frames, every page at every breakpoint, from the repo's own e2e harness (`nix run .#figma`). Use when asked to put/drop/dump/render/push the site, landing or its pages into Figma, to get a Figma snapshot of what the code renders now, or to lay out all breakpoints side by side in Figma for rearranging by hand."
license: "BlueOak-1.0.0"
compatibility: "a repo whose flake has `apps.figma` over `@evinvest/figma-render` (sites_tools' mkLanding, site_conductor); Figma MCP `create_new_file` only to create a render board"
metadata:
  version: "0.6.0"
---

# figma-render

Figma here is a debug artifact, like a flamegraph: code stays the source of truth, nothing is read back. The
frames come from the repo's Playwright harness (same pinned Chromium, viewports, A/B control cookies and
settle as its screenshot baselines), which serializes each page into Figma through `generate_figma_design`'s
capture script. `html_to_figma` re-renders on Figma's side and would lose the viewports, so it is not an
alternative.

The whole render is one command, run from the repo root:

- `nix run .#figma` builds the site and renders every page it crawls onto a new page `<short sha> <YYYY-MM-DD>[ dirty]`
  of `file`, named `<project> <page>`, a row per page and a column per project. Its stdout is the page's link.

- `nix run .#figma -- --folder <figma folder URL> --name <file>` renders into the file `<file>` of that folder
  instead (created if missing, left holding only the new page); it needs `FIGMA_TOKEN`, a Figma personal access token
  with `folders:read`. v_flakes `github.figma = { on = "gha" | "publish"; }` runs exactly that into the file named after
  the repo in the org variable `FIGMA_FOLDER`: "gha", `figma.yml` on a `v*` tag or a `[figma]` comment; "publish",
  `nix run .#publish` (`github.publish`) after pushing the tag, for a render that needs this machine's data.

What gets rendered is what a crawl reaches from the repo's SECTIONS: `defineFigmaSuite({ test }, sections, { hide?, exclude? })`,
each section `{ name, url, selector }` a page to start from. Every same-origin `<a href>` is followed; pages differing
only in numbers (ids, coordinates) are one frame; `exclude` keeps links that act (sign-out) or lead to another app out.
A state no link reaches has no frame: put it in the URL (site_conductor keeps its UI state in query keys) and add a
section for it. Missing pages mean missing links, or a stack without the data that draws them.

Both are `evinvest-figma-render`, the bin of `@evinvest/figma-render` (EV-Main/web_std `ts/figma-render`,
`~/s/ev/web_std`), over the repo's `defineFigmaSuite` specs. It is its own client of Figma's MCP server and
spends one rate-limited call per render (`use_figma`; issuing and polling capture ids is exempt). Landings get
it through sites_tools' `@evinvest/sites-tools/testing/e2e` (`defineSectionSuite` calls it on the baseline
sections; `defineFigmaSuite` re-exported) and `nix/mk-landing.nix` (`~/s/ev/_sa/sites/tools`), their sections in
`tests/e2e/sections.spec.ts`; site_conductor in `frontend/tests/e2e/figma.spec.ts` and its flake. Read those when the repo side misbehaves.

## The loop

1. If the flake has no `figmaFile`, the repo has no render board yet: load `figma-create-new-file`, create a design
   file `<pname> — renders` (separate from the brand's design file, which stays hand-made) in the plan the
   other render boards live in ("EV Invest's team"), then set `figmaFile = "<key>";` in the repo's flake
   (`mkLanding`'s argument, or the `figmaFile` binding) and commit it.
2. Run `nix run .#figma` in the background; the build is most of its time. The first run on a machine prints a
   Figma login URL and opens it in the browser: relay it to the user and wait.
3. Relay the link it prints. A non-zero exit names each frame that was not captured: its test failed, and the
   run log says why. Fix and re-run; a re-run makes a new page.
