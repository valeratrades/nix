{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/NIXPKGS_VERSION";
    nixpkgs-python.url = "github:cachix/nixpkgs-python";
    devenv.url = "github:cachix/devenv";
    git-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github";
  };

  outputs =
    { self
    , nixpkgs
    , devenv
    , git-hooks
    , v-utils
    , ...
    } @ inputs:
    let
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forEachSystem = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) systems);
    in
    {
      packages = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pname = "PROJECT_NAME_PLACEHOLDER";
        in
        {
          default = pkgs.writeShellScriptBin "${pname}" ''
            export PYTHONPATH="${self}:$PYTHONPATH"
            python -m src "$@"
          '';
        }
      );

      devShells = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pname = "PROJECT_NAME_PLACEHOLDER";

          workflowContents = v-utils.ci {
            inherit pkgs;
            lastSupportedVersion = "";
            jobsErrors = [ ];
            jobsWarnings = [ "tokei" ];
          };
          readme = v-utils.readme-fw {
            inherit pkgs pname;
            lastSupportedVersion = "python-3.12";
            rootDir = ./.;
            licenses = [
              {
                name = "Blue Oak 1.0.0";
                outPath = "LICENSE";
              }
            ];
            badges = [
              "msrv"
              "loc"
              "ci"
            ];
          };
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              {
                # https://devenv.sh/reference/options/
                packages = with pkgs; [
                  mold-wrapped
                  uv
                ];

                scripts = {
                  uv_sync = {
                    exec = "uv sync --prerelease=allow --no-install-project --dev";
                  };
                };

                languages.python = {
                  enable = true;
                  version = "3.12";
                  uv.enable = true;
                  uv.sync.enable = false;
                };

                git-hooks.hooks = {
                  treefmt.enable = true;
                  ruff.enable = true;
                  ruff-format.enable = true;
                  mypy.enable = true;
                };

                enterShell = ''
                  mkdir -p ./.github/workflows
                  rm -f ./.github/workflows/errors.yml; cp ${workflowContents.errors} ./.github/workflows/errors.yml
                  rm -f ./.github/workflows/warnings.yml; cp ${workflowContents.warnings} ./.github/workflows/warnings.yml

                  cp -f ${v-utils.files.licenses.blue_oak} ./LICENSE

                  cargo -Zscript -q ${v-utils.hooks.appendCustom} ./.git/hooks/pre-commit
                  cp -f ${(v-utils.hooks.treefmt) { inherit pkgs; }} ./.treefmt.toml
                  cp -f ${(v-utils.hooks.preCommit) { inherit pkgs pname; }} ./.git/hooks/custom.sh

                  cp -f ${
                    (v-utils.files.gitignore {
                      inherit pkgs;
                      langs = [ "py" ];
                    })
                  } ./.gitignore

                  cp -f ${readme} ./README.md

                  if [ -f .devenv/state/venv/bin/activate ]; then
                    source .devenv/state/venv/bin/activate
                  else
                    uv venv >/dev/null
                    source .devenv/state/venv/bin/activate
                  fi
                  if [ ! -f uv.lock ]; then
                    uv_sync
                  fi
                '';
              }
            ];
          };
        }
      );
    };
}
