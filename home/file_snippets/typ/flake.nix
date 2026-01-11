{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github?ref=v1.4";
  };
  outputs = { self, nixpkgs, flake-utils, pre-commit-hooks, v-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          allowUnfree = true;
        };
        pre-commit-check = pre-commit-hooks.lib.${system}.run (v-utils.files.preCommit { inherit pkgs; });
        pname = "PROJECT_NAME_PLACEHOLDER";

        github = v-utils.github {
          inherit pkgs pname;
          lastSupportedVersion = "";
          langs = [ ];
          jobs.default = false;
        };
        readme = v-utils.readme-fw {
          inherit pkgs pname;
          lastSupportedVersion = "";
          rootDir = ./.;
          default = true;
          badges = [ "loc" ];
        };
      in
      {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-document";
          src = ./.;

          nativeBuildInputs = [ pkgs.typst ];

          buildPhase = ''
            typst compile __main__.typ output.pdf
          '';

          installPhase = ''
            mkdir -p $out
            cp output.pdf $out/
          '';
        };

        devShells.default =
          with pkgs;
          mkShell {
            shellHook =
              pre-commit-check.shellHook
              + github.shellHook
              + readme.shellHook
              + ''
                cp -f ${(v-utils.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
              '';

            packages = [
              typst
            ] ++ pre-commit-check.enabledPackages ++ github.enabledPackages;
          };
      }
    );
}
