# The rpi5 nixosSystem, built via nixos-raspberrypi (own nixpkgs + vendor
# kernel/firmware), deliberately NOT wired through the x86_64 machinery in
# outputs/default.nix. Kept here so the whole host lives in one folder.
{ inputs, self, mylib, myvars, ... }:
inputs.nixos-raspberrypi.lib.nixosSystem {
  specialArgs = { inherit self inputs mylib; user = myvars.valera; };
  modules = [
    ./default.nix
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit self inputs mylib;
        user = myvars.valera;
      };
      home-manager.users.admin = import ./home.nix;
    }
  ];
}
