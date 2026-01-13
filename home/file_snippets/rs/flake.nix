{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    v-utils.url = "github:valeratrades/.github?ref=v1.4";
  };
  outputs = { self, nixpkgs, rust-overlay, flake-utils, pre-commit-hooks, v-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
          allowUnfree = true;
        };
        #NB: can't load rust-bin from nightly.latest, as there are week guarantees of which components will be available on each day.
        rust = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
          extensions = [ "rust-src" "rust-analyzer" "rust-docs" "rustc-codegen-cranelift-preview" ];
        });
        pre-commit-check = pre-commit-hooks.lib.${system}.run (v-utils.files.preCommit { inherit pkgs; });
        manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
        pname = manifest.name;
        stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv;

        rs = v-utils.rs { inherit pkgs rust; };
        github = v-utils.github {
          inherit pkgs pname rs;
          lastSupportedVersion = "CURRENT_NIGHTLY_BY_DATE";
          langs = [ "rs" ];
          jobs.default = true;
        };
        readme = v-utils.readme-fw {
          inherit pkgs pname;
          defaults = true;
          lastSupportedVersion = "nightly-RUSTC_CURRENT_VERSION";
          rootDir = ./.;
          badges = [ "msrv" "crates_io" "docs_rs" "loc" "ci" ];
        };
        combined = v-utils.utils.combineModules [ rs github readme ];
      in
      {
        packages =
          let
            rustc = rust;
            cargo = rust;
            rustPlatform = pkgs.makeRustPlatform {
              inherit rustc cargo stdenv;
            };
          in
          {
            default = rustPlatform.buildRustPackage {
              inherit pname;
              version = manifest.version;

              buildInputs = with pkgs; [
                openssl.dev
              ];
              nativeBuildInputs = with pkgs; [ pkg-config ];

              cargoLock.lockFile = ./Cargo.lock;
              src = pkgs.lib.cleanSource ./.;
            };
          };

        devShells.default =
          with pkgs;
          mkShell {
            inherit stdenv;
            shellHook =
              pre-commit-check.shellHook
              + combined.shellHook
              + ''
                cp -f ${(v-utils.files.treefmt) { inherit pkgs; }} ./.treefmt.toml
              '';

            packages = [
              mold
              openssl
              pkg-config
              rust
            ] ++ pre-commit-check.enabledPackages ++ combined.enabledPackages;

						env.RUST_BACKTRACE = 1;
						env.RUST_LIB_BACKTRACE = 0;
          };
      }
    );
}
