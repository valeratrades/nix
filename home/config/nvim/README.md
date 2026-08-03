All shortcuts are configured with **Semimak** keyboard layout in mind.

I use lazy for plugin manager, but the configurations for plugins are implemented in the old style

# Rust Integration
This config supports writing Neovim functions in Rust using `nvim-oxi`. See [rust_plugins/README.md](rust_plugins/README.md) for details on adding and building Rust functions.

# Verse
Editing support only — highlighting, `#` comments, 4-space offside indent. There is
deliberately no LSP, no formatter and no treesitter parser:

- Epic ships no Verse compiler or language server for Linux. Both are Win64 binaries
  (`VerseCLRVM-Win64-Shipping.exe`, `verse-lsp-latest.exe`) living inside a UEFN/Fortnite
  install, and UEFN doesn't run on Linux. Verse is also sandboxed — no filesystem, sockets
  or argv — so it cannot express a standalone CLI program in the first place.
- Both public tree-sitter grammars have unbounded-memory parse bugs.
  `MattAMonroe/tree-sitter-verse` hangs on essentially every file;
  `Unoqwy/tree-sitter-verse` hangs on ~3% of real Verse — a 3-line snippet from the Book of
  Verse drove it to 3.9GB in 27s, and unbounded it reached 40GB and took the desktop down.
  Note `overlays/tree-sitter-memcap.nix` caps the *CLI* only; nvim parses in-process and
  would not have been protected.

`syntax/verse.vim` uses vim's regex engine instead, which is bounded by construction:
48MB peak and 26s to highlight every column of all 1238 files in Epic's test corpus plus
the Book of Verse snippets.

# Tips
- put `Esc` on capslock (tap). Put control there too (hold), - with [keyd](<https://github.com/rvaiya/keyd>), [kanata](<https://github.com/jtroo/kanata>), etc, it's possible to map one action when the key is **held**, another when it's **tapped**.
- ensure shifts are one-shot (refer to [keyd](<https://github.com/rvaiya/keyd>)'s definition)
