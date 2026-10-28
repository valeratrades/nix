let
  cfg = rec {
    stale_after_days = 30; # shell nags to run `up` once the last run is older; not used (files: max(atime, mtime), dirs: mtime) for this long is stale
    warn_probability = 0.2; # chance a shell start nags, once due
    stale_multipliers = { llm_worktrees = 0.2; redirects = 1.0; }; # of stale_after_days; floats, as v_utils::Percent reads an int as percents

    # a dir holding any of these is one unit, kept or removed whole; `*` prefix matches by suffix
    unit_markers = [
      ".git" "HEAD" "Cargo.toml" "flake.nix" "package.json" "pyproject.toml" "go.mod"
      "lakefile.lean" "lakefile.toml" "typst.toml" "pyvenv.cfg" "*.dist-info" "Local State"
    ];

    cache_limit_gb = 20; # past it after the outdated sweep, least recently used ~/.cache units go first
  };
in
assert cfg.warn_probability >= 0 && cfg.warn_probability <= 1;
cfg
