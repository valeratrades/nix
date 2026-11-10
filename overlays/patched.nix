# Packages we build from patched source. They sit on `nixpkgs-patched` rather than `nixpkgs`, so a
# dependency bump leaves them untouched; `nixup --patches` is the one place that moves it.
inputs: final: prev:
let
  base = import inputs.nixpkgs-patched { localSystem = prev.stdenv.hostPlatform.system; };
in
{
  patched = {
    # wtype hands out keycodes 1..N in order of first use, and Chromium reads those as physical
    # keys: pasting text with enough distinct chars sent F5/Ctrl/Alt/Power/BrowserBack into Chrome.
    wtype = base.wtype.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./wtype-safe-keycodes.patch ];
    });

    # bare `49…`/`+49…` dials gain the `000` prefix
    baresip = base.baresip.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./baresip-de-000-prefix.patch ];
    });

    # a lone matching passkey answers without its confirm dialog
    keepassxc = base.keepassxc.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./keepassxc-passkey-no-confirm.patch ];
    });

    # Without systemd, panes are plain children of the server instead of tmux-spawn-*.scope units,
    # whose broken cgroup state made shutdown ride out the full stop timeout.
    # See ongoing_debug/2026-06-05_slow-shutdown.md.
    tmux = base.tmux.override { withSystemd = false; };

    # `{nix,flake}-profile*` also matches `flake-tmp-profile.*`, deleting the tmp profile before its GC root is made.
    #WAIT: https://github.com/nix-community/nix-direnv/issues/546
    #WAIT: https://github.com/direnv/direnv/issues/1181
    # Both `-eq 1` guards end in `_nix_import_env "$profile_rc"` without consulting `profile_missing`, so a cache
    # whose closure was GC'd still gets sourced, replaying a shellHook of dangling store paths. Staleness may be
    # ignored, absence must rebuild.
    # Under manual reload the watched-files staleness scan and the watches themselves are skipped: their only
    # consumer there is the out-of-date warning. `dirr` deletes the .rc, which rebuilds via profile_rc_missing.
    # A failed load (e.g. v_flakes' generation guard) keeps no `watch_file` — not even the .rc — so the reload
    # touches .envrc, the one file direnv still watches, for open shells to pick the rebuilt cache up.
    nix-direnv = base.nix-direnv.overrideAttrs (old: {
      # ahead of resholve, so commands introduced here get resolved too
      preFixup = ''
        chmod u+w $out/share/nix-direnv/direnvrc
        substituteInPlace $out/share/nix-direnv/direnvrc \
          --replace-fail '{nix,flake}-profile*' '{nix-profile-,flake-profile-}*' \
          --replace-fail '_nix_direnv_force_reload=1 direnv exec "$PWD" true' '_nix_direnv_force_reload=1 direnv exec "$PWD" true
touch "$PWD/.envrc"' \
          --replace-fail '_nix build --out-link "$symlink" "$storepath"' '_nix build --out-link "$symlink" "$(readlink -f "$storepath")"' \
          --replace-fail 'if [[ $_nix_direnv_manual_reload -eq 1 && -z ''${_nix_direnv_force_reload-} ]]; then' 'if [[ $_nix_direnv_manual_reload -eq 1 && $profile_missing -eq 0 && $profile_rc_missing -eq 0 && -z ''${_nix_direnv_force_reload-} ]]; then' \
          --replace-fail 'if [[ $_nix_direnv_allow_fallback -eq 1 ]]; then' 'if [[ $_nix_direnv_allow_fallback -eq 1 && $profile_missing -eq 0 && $profile_rc_missing -eq 0 ]]; then' \
          --replace-fail '  _nix_direnv_watches watches' '  [[ $_nix_direnv_manual_reload -eq 1 && -z ''${_nix_direnv_force_reload-} ]] || _nix_direnv_watches watches' \
          --replace-fail '  watch_file "''${files_to_watch[@]}"' '  [[ $_nix_direnv_manual_reload -eq 1 && -z ''${_nix_direnv_force_reload-} ]] || watch_file "''${files_to_watch[@]}"'
      '' + old.preFixup;
    });

    # canvas npm package doesn't build with nodejs v24's V8 API changes
    excalidraw_export = base.excalidraw_export.override { buildNpmPackage = base.buildNpmPackage.override { nodejs = base.nodejs_22; }; };

    # opt-in (user.optional_patches): a 10+ min C++ build.
    # valeratrades/nixd@schema-directive reads a `#:schema <module>` first line and types that file
    # against the module's options. Drop once upstream has it; RFC at nix-community/nixd#889.
    nixd = base.callPackage (base.fetchFromGitHub {
      owner = "valeratrades";
      repo = "nixd";
      rev = "7fcdc56452ccfe2c37ca66b1b70fd440f6a473e5";
      hash = "sha256-cyvikKVDVvuwAjxDyXNEZF7vmbakHfET5at0fbwyEds=";
    }) {
      # the versions nixd's own flake builds against
      nixComponents = base.nixVersions.nixComponents_2_34;
      llvmPackages = base.llvmPackages_21;
    };
  };
}
