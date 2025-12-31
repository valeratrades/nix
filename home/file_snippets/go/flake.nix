{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github?ref=v1.2";
    go-warn-unused.url = "github:valeratrades/go-warn-unused";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , pre-commit-hooks
    , v-utils
    , go-warn-unused
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          allowUnfree = true;
          overlays = [ go-warn-unused.overlays.default ];
        };

        pre-commit-check = pre-commit-hooks.lib.${system}.run (v-utils.files.preCommit { inherit pkgs; });
        pname = "PROJECT_NAME_PLACEHOLDER";
        stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv;

        github = v-utils.github {
          inherit pkgs pname;
          lastSupportedVersion = "";
          jobsErrors = [ "go-tests" ];
          jobsWarnings = [
            "tokei"
            "go-gocritic"
            "go-security-audit"
          ];
          jobsOther = [ "loc-badge" ];
          langs = [ "go" ];
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
              + github.shellHook
              + ''
                cp -f ${v-utils.files.licenses.blue_oak} ./LICENSE

                cp -f ${(v-utils.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
                cp -f ${ (v-utils.files.gitLfs { inherit pkgs; }) } ./.gitattributes
                cp -f ${(v-utils.files.golang.gofumpt { inherit pkgs; })} ./gofumpt.toml

                cp -f ${readme} ./README.md
              '';

            packages = [
              go  # patched with -nounusederrors support
              mold
            ] ++ pre-commit-check.enabledPackages ++ github.enabledPackages;
          };
      }
    );
}
