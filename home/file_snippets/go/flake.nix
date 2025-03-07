{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , pre-commit-hooks
    , v-utils
    ,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          allowUnfree = true;
        };

        pre-commit-check = pre-commit-hooks.lib.${system}.run (v-utils.files.preCommit { inherit pkgs; });
        pname = "PROJECT_NAME_PLACEHOLDER";
        stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv;

        workflowContents = v-utils.ci {
          inherit pkgs;
          lastSupportedVersion = "";
          jobsErrors = [ "go-tests" ];
          jobsWarnings = [
            "tokei"
            "go-gocritic"
            "go-security-audit"
          ];
        };
        readme = v-utils.readme-fw {
          inherit pkgs pname;
          lastSupportedVersion = "go-GOLANG_VERSION";
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
        #TODO!: \
        #packages.default = pkgs.buildGoPackage rec {
        #  inherit pname;
        #  version = "0.1.0";
        #  src = ./.;
        #};

        devShells.default =
          with pkgs;
          mkShell {
            inherit stdenv;
            shellHook =
              pre-commit-check.shellHook
              + ''
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
                    langs = [ "go" ];
                  })
                } ./.gitignore
                cp -f ${(v-utils.files.golang.gofumpt { inherit pkgs; })} ./gofumpt.toml

                cp -f ${readme} ./README.md
              '';

            packages = [
              mold-wrapped
            ] ++ pre-commit-check.enabledPackages;
          };
      }
    );
}
