{
  inputs.sops-nix.url = "github:Mic92/sops-nix";
  #inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, sops-nix }: {
    #NB: hostname
    nixosConfigurations.vlaptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./os/nixos/configuration.nix
        sops-nix.nixosModules.sops
      ];
    };
  };
}
