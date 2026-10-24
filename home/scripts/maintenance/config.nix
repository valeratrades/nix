rec {
  warn_after_days = 30; # shell nags to run `up` once the last run is older
  outdated_after_days = warn_after_days * 2; # not used (files: max(atime, mtime), dirs: mtime) for this long

  # a dir holding any of these is one unit, kept or removed whole; `*` prefix matches by suffix
  unit_markers = [
    ".git" "HEAD" "Cargo.toml" "flake.nix" "package.json" "pyproject.toml" "go.mod"
    "lakefile.lean" "lakefile.toml" "typst.toml" "pyvenv.cfg" "*.dist-info" "Local State"
  ];

  redirect_unused_days = 30; # `redirects/` hop not traversed for this long: old path and hop are removed
  cache_limit_gb = 20; # past it after the outdated sweep, least recently used ~/.cache units go first
}
