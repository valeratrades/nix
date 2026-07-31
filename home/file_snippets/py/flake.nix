{
  nixConfig = {
    extra-substituters = [ "https://valeratrades.cachix.org" ];
    extra-trusted-public-keys = [ "valeratrades.cachix.org-1:gXVwhzO5YB+BaiEJYT48qZgzdaErGQew6xtZcz4Fo1Q=" ];
  };

  inputs = {
    v_flakes.url = "github:valeratrades/v_flakes?ref=v1.6";
  };

  outputs = { self, v_flakes }:
    let
      inherit (v_flakes) flake-utils pre-commit-hooks;
      pname = "PROJECT_NAME_PLACEHOLDER";
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import v_flakes.default_nixpkgs { inherit system; };
        # pyproject_merge.rs / append_custom.rs are `cargo -Zscript`, so even a
        # python-only shell needs a nightly toolchain on PATH via `combine`.
        rust = v_flakes.rs.default_nightly system;
        pre-commit-check = pre-commit-hooks.lib.${system}.run (v_flakes.files.preCommit { inherit pkgs; });

        # `.venv` is uv's default project environment, so `uv sync` here targets
        # the same venv the shell activates and the same one CI builds.
        py = v_flakes.py { inherit pkgs; src_path = "src"; venv_path = ".venv"; };
        github = v_flakes.github {
          inherit pkgs pname py;
          # `enable` asserts on `rs.rust` (its hook install is a cargo -Zscript),
          # but passing `rs` would infer rust into `langs` and emit rust CI jobs.
          rs = { inherit rust; };
          langs = [ "py" ];
          enable = true;
          lastSupportedVersion = "python-${py.python.pythonVersion}";
          jobs.default = true;
          gitignore.extra = "*.egg-info/";
          publishCachix = "valeratrades";
        };
        readme = v_flakes.readme-fw {
          inherit pkgs pname;
          defaults = true;
          lastSupportedVersion = "python-${py.python.pythonVersion}";
          rootDir = ./.;
          repo = "GITHUB_USER/PROJECT_NAME_PLACEHOLDER";
          badges = [ "msrv" "loc" "ci" ];
        };
        combined = v_flakes.utils.combine { inherit rust; modules = [ py github readme ]; };
        # Same invocation the py-tests workflow uses.
        uv_sync = pkgs.writeShellScriptBin "uv_sync" "uv sync --prerelease=allow --no-install-project --dev";
      in
      {
        # Runtime deps are listed here rather than resolved from pyproject.toml —
        # nix has no uv resolver, so the two lists must be kept in sync by hand.
        packages.default =
          let pyEnv = py.python.withPackages (ps: with ps; [ loguru typeguard icecream ]);
          in pkgs.writeShellScriptBin pname ''
            export PYTHONPATH="${self}:$PYTHONPATH"
            exec ${pyEnv}/bin/python -m src "$@"
          '';

        devShells.default = pkgs.mkShell {
          shellHook =
            pre-commit-check.shellHook
            + combined.shellHook
            + ''
              cp -f ${(v_flakes.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
              # Unconditional: uv.lock is committed, so gating on its absence left a
              # fresh clone with an empty venv and no warning. Idempotent and ~1s.
              uv_sync
            '';

          packages = [ uv_sync ]
            ++ pre-commit-check.enabledPackages
            ++ combined.enabledPackages;
        };
      }
    );
}
