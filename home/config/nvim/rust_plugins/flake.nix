{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
    v-utils.url = "github:valeratrades/.github";
  };

  outputs = { nixpkgs, rust-overlay, flake-utils, v-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rust = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
          extensions = [ "rust-src" "rust-analyzer" "rust-docs" "rustc-codegen-cranelift-preview" ];
        });
        manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
        pname = manifest.name;
        stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.stdenv;
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
            default = rustPlatform.buildRustPackage rec {
              inherit pname;
              version = manifest.version;

              cargoLock.lockFile = ./Cargo.lock;
              src = pkgs.lib.cleanSource ./.;

              # Build only the library, don't try to install binaries
              buildPhase = ''
                runHook preBuild
                cargo build --release --lib
                runHook postBuild
              '';

              # Install: copy the built library to output and to Neovim plugin location
              installPhase = ''
                runHook preInstall
                mkdir -p $out/lib
                cp target/release/librust_plugins.so $out/lib/rust_plugins.so

                # Also install to the lua directory if we're in the source tree
                if [ -d "../lua" ]; then
                  cp target/release/librust_plugins.so ../lua/rust_plugins.so #HACK: creates files outside of current directory
                  echo "✓ Plugin installed to ../lua/rust_plugins.so"
                fi
                runHook postInstall
              '';

              # Skip cargo install since we're handling installation manually
              doCheck = false;
            };
          };

        devShells.default = with pkgs; mkShell {
          inherit stdenv;
          shellHook = ''
            # Copy v-utils config files (excluding .cargo/config.toml which has nightly flags)
            cp -f ${(v-utils.files.rust.rustfmt {inherit pkgs;})} ./rustfmt.toml
            cp -f ${(v-utils.hooks.treefmt) { inherit pkgs; }} ./.treefmt.toml

            echo "Rust plugin dev environment loaded"
            echo "Run 'nix build' to compile and install the plugin"
          '';

          env = {
            RUST_BACKTRACE = 1;
            RUST_LIB_BACKTRACE = 0;
          };

          packages = [
            mold-wrapped
            pkg-config
            rust
          ];
        };
      }
    );
}
