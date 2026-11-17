let
  cfg = rec {
    # v_utils::Timeframe: `M` is months, `m` minutes. Not used (files: max(atime, mtime), dirs: mtime) for a horizon is stale
    horizon_long = "1M"; # shell nags to run `up` once overdue by it; default for what goes stale
    horizon_fast = "1w"; # what piles up fast: ~/.cargo/build (a dir per script path, and every switch moves fish's scripts to a new /nix/store path), LLM worktrees
    warn_probability = 0.2; # chance a shell start nags, once due

    # a dir holding any of these is one unit, kept or removed whole; `*` prefix matches by suffix
    unit_markers = [
      ".git" "HEAD" "Cargo.toml" "flake.nix" "package.json" "pyproject.toml" "go.mod"
      "lakefile.lean" "lakefile.toml" "typst.toml" "pyvenv.cfg" "*.dist-info" "Local State"
    ];

    cache_limit_gb = 20; # past it after the outdated sweep, least recently used ~/.cache units go first
    cache_self_managed = [ "kache" ]; # ~/.cache dirs whose tool bounds its own size; a file removed under one is a hole in its index
  };
in
assert cfg.warn_probability >= 0 && cfg.warn_probability <= 1;
cfg
