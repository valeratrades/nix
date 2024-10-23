{ pkgs, ... }:

let
  fenix = builtins.getFlake "github:nix-community/fenix";
in
{
  nixpkgs.overlays = [ fenix.overlays.default ];

  environment.systemPackages = with pkgs; [
    (fenix.packages.x86_64-linux.complete.withComponents [
      "cargo"
      "clippy"
      "rust-src"
      "rustc"
      "rustfmt"
    ])
    rust-analyzer-nightly
  ];
}

