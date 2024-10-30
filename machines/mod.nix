{ self, inputs, ... }:
{
  flake.nixosModules.default = ./modules/default.nix;
}
