---
name: v_flakes
description: "Rules for working in ~/s/v_flakes (the shared Nix parts collection consumed by every other repo via `v_flakes.url = github:valeratrades/v_flakes?ref=v1.6`). Read BEFORE editing anything under ~/s/v_flakes, and before changing how any repo consumes v_flakes — covers how to release, what the pin policy is, and what re-exports exist."
---

# v_flakes

Shared Nix parts. Every consumer repo pins exactly one input:

```nix
inputs.v_flakes.url = "github:valeratrades/v_flakes?ref=v1.6";
```

and takes everything else off the re-exports — never its own `nixpkgs` / `flake-utils` /
`rust-overlay` / `pre-commit-hooks` / `flake-parts` / `process-compose-flake` / `devenv` input.

```nix
outputs = { self, v_flakes }:
  let inherit (v_flakes) flake-utils pre-commit-hooks; in
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import v_flakes.default_nixpkgs { inherit system; config.allowUnfree = true; };
      rust = v_flakes.rs.default_nightly system;
    in { ... });
```

`default_nixpkgs` is a bare source tree for `import`; `v_flakes.nixpkgs` is the same rev as a
flake, for consumers that need `.lib` (or that pass `inputs.nixpkgs` on to a third-party
flakeModule, as devenv's does).

## Releasing

```
cnix_release --ignore-cargo --patch --fast
```

Run it from `main`, tree clean. It pushes `main`, force-updates `release` / `v1` / `v1.6`, and
tags `v1.6.N`. `__scripts/release.sh` is the slow path (runs `cargo t` + `cargo release` first) —
use it only when `src/` changed.

Then bump every consumer: `nix flake update` in each repo under `~/s/ev_invest` and the other
`~/s` repos that pin v_flakes, and commit the lock.

## Pin policy

`default_nixpkgs.nix` and `rs/default_nightly.nix` fork the toolchain derivation for the whole
fleet. Moving either requires at least a MINOR bump (a new `vX.Y` branch), never a patch.

## Adding an input

Anything added here lands in every consumer's lock. Follow the nested `nixpkgs` of whatever you
add (`<input>.inputs.<sub>.inputs.nixpkgs.follows = "nixpkgs"`) — the devShell prints a
duplicate-input warning with the wasted size if you miss one. Verify with:

```
nix flake metadata --json | jq '[.locks.nodes|to_entries[]|select(.value.locked.repo=="nixpkgs")]|length'
```

It must be 1.

## Generated files

`.cargo/config.toml`, `.github/workflows/*`, `README.md`, `.gitignore`, `.treefmt.toml` are
written by v_flakes' own shellHook. They drift dirty on shell entry; that is normal, and the
release commits them.
