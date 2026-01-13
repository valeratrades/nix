{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/NIXPKGS_VERSION";
    nixpkgs-python.url = "github:cachix/nixpkgs-python";
    devenv.url = "github:cachix/devenv";
    git-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github?ref=v1.4";
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

          github = v-utils.github {
            inherit pkgs pname;
            lastSupportedVersion = "";
            langs = [ "py" ];
            jobs.default = true;
          };
          readme = v-utils.readme-fw {
            inherit pkgs pname;
            defaults = true;
            lastSupportedVersion = "python-3.12";
            rootDir = ./.;
            badges = [
              "msrv"
              "loc"
              "ci"
            ];
          };
          combined = v-utils.utils.combineModules [ github readme ];
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              {
                # https://devenv.sh/reference/options/
                packages = with pkgs; [
                  mold
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

                enterShell =
                  combined.shellHook +
                  ''
                  cp -f ${(v-utils.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
                  cp -f ${ (v-utils.files.gitLfs { inherit pkgs; }) } ./.gitattributes

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
