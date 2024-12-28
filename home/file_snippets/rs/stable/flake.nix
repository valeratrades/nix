{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      perSystem =
        {
          lib,
          pkgs,
          system,
          config,
          ...
        }:
        {
          packages =
            let
              manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
            in
            {
              default = pkgs.rustPlatform.buildRustPackage rec {
                pname = manifest.name;
                version = manifest.version;

                buildInputs = with pkgs; [
                  openssl
                  openssl.dev
                ];
                nativeBuildInputs = with pkgs; [ pkg-config ];
                env.PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

                cargoLock.lockFile = ./Cargo.lock;
                src = pkgs.lib.cleanSource ./.;
              };
            };
        };
    };
}
