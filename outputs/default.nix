inputs@{
  self,
  nixpkgs,
  home-manager,
  pre-commit-hooks,
  ...
}:
let
  inherit (inputs.nixpkgs) lib;
  #TODO!!: integrate ryan's myLib and myVars into my setup
  mylib = import ../lib { inherit lib; };
  myvars = import ../vars { inherit lib; };

  # Add my custom lib, vars, nixpkgs instance, and all the inputs to specialArgs,
  # so that I can use them in all my nixos/home-manager/darwin modules.
  genSpecialArgs =
    system:
    inputs
    // {
      inherit mylib myvars;

      # use unstable branch for some packages to get the latest updates
      #HACK: stone from ryan (as everything here), and currently are not used.
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system; # refer the `system` parameter form outer scope recursively
        # To use chrome, we need to allow the installation of non-free software
        config.allowUnfree = true;
      };
      pkgs-stable = import inputs.nixpkgs-stable {
        inherit system;
        # To use chrome, we need to allow the installation of non-free software
        config.allowUnfree = true;
      };
    };
  args = {
    inherit
      inputs
      lib
      mylib
      myvars
      genSpecialArgs
      ;
  };

  nixosSystems = {
    x86_64-linux = import ./x86_64-linux (args // { system = "x86_64-linux"; });
    # aarch64-linux = import ./aarch64-linux (args // {system = "aarch64-linux";});
    # riscv64-linux = import ./riscv64-linux (args // {system = "riscv64-linux";});
  };
  darwinSystems = {
    #aarch64-darwin = import ./aarch64-darwin (args // {system = "aarch64-darwin";});
    #x86_64-darwin = import ./x86_64-darwin (args // {system = "x86_64-darwin";});
  };
  allSystems = nixosSystems // darwinSystems;
  allSystemNames = builtins.attrNames allSystems;

  forAllSystems = func: (nixpkgs.lib.genAttrs allSystemNames func); # NB: stolen from ryan, it's likely I'm misusing some part of this.
  user-vars = [
    myvars.valera
    myvars.timur
    myvars.maria
  ];
  user = myvars.valera; # dbg
in
{
  # Add attribute sets into outputs, for debugging
  debugAttrs = {
    inherit
      nixosSystems
      darwinSystems
      allSystems
      allSystemNames
      ;
  };

  # NixOS Hosts
  #nixosConfigurations =
  #  lib.attrsets.mergeAttrsList (map (it: it.nixosConfigurations or {}) nixosSystemValues);

  packages.x86_64-linux.wlr-gamma-service =
    inputs.nixpkgs-2405.legacyPackages.x86_64-linux.callPackage
      (builtins.fetchGit {
        url = "https://github.com/nobbz/wlr-brightness";
        rev = "1985062bf08086e6145db4ef1a292b535fd9f1a1";
        #sha256 = "sha256-QZhtI10qKu6qUePZ1rKaH3SBoUZ30+w8xcc5bBRYbGw=";
        #fetchSubmodules = true;
        submodules = true;
      })
      { };
  #packages = forAllSystems (
  #   system: allSystems.${system}.packages or {}
  # );

  #NB: when writing hostname, remove all '_' characters
  #nixosConfigurations."${user.desktopHostName}" = nixpkgs.lib.nixosSystem {
  nixosConfigurations = lib.genAttrs (map (user: user.desktopHostName) user-vars) (
    desktopHostName:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = {
        inherit inputs self;
        inherit mylib user; # HACK
      };

      modules = [
        (mylib.relativeToRoot "os/nixos/configuration.nix")
        (mylib.relativeToRoot "machines/modules/default.nix")

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup"; # delusional home-manager wants this exact file-extension for when I backup system-level files
          home-manager.extraSpecialArgs = {
            inherit inputs self;
            inherit mylib user; # HACK
          };

          #home-manager.sharedModules = [
          #	inputs.sops-nix.homeManagerModules.sops
          #];

          home-manager.users."${user.username}" = import (
            mylib.relativeToRoot "hosts/${user.desktopHostName}/default.nix"
          );
          nix.settings.trusted-users = [ user.username ]; # all systems assume single-user configurations
        }

        #({ pkgs, ... }: import ./modules/fenix.nix { inherit pkgs; })
      ];
    }
  );

  checks = forAllSystems (system: {
    #TODO!!: \
    #		# eval-tests per system
    #		eval-tests = allSystems.${system}.evalTests == {};
    #
    #TODO!: figure out how to make it continue after formatting something
    pre-commit-check = pre-commit-hooks.lib.${system}.run {
      src = mylib.relativeToRoot ".";
      hooks = {
        #alejandra.enable = true; # formatter
        nixfmt-rfc-style.enable = true; # formatter

        #				# Source code spell checker
        #				typos = {
        #					enable = true;
        #					settings = {
        #						write = true; # Automatically fix typos
        #						configPath = "./.typos.toml"; # relative to the flake root
        #					};
        #				};
        #prettier =
        #	enable = true;
        #	settings = {
        #		write = true; # Automatically format files
        #		configPath = "./.prettierrc.yaml"; # relative to the flake root
        #	};
        #};
        #dbg: temporarily disabled
        #deadnix.enable = true; # detect unused variable bindings in `*.nix`
        statix.enable = true; # lints and suggestions for Nix code(auto suggestions)
      };
    };
  });

  # Development Shells
  devShells = forAllSystems (
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      default = pkgs.mkShell {
        packages =
          with pkgs;
          lib.lists.flatten [
            fish
            # fix `cc` replaced by clang, which causes nvim-treesitter compilation error
            gcc
            [
              # Nix-related
              #alejandra
              nixfmt-rfc-style
              deadnix
              statix
            ]
            typos # spell checker
            nodePackages.prettier # code formatter
          ];
        name = "dots"; # TODO: figure out what this `name` means
        shellHook = ''
          ${self.checks.${system}.pre-commit-check.shellHook}
        '';
      };
    }
  );

  formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
}
## Ex of building for different users:
#inherit (self) outputs;
#    inherit (nixpkgs) lib;
#    inherit (lib) mapAttrs;
#    sharedModules = [
#      meat.nixosModules.meat
#      madness.nixosModules.madness
#      nur.nixosModules.nur
#      nix-index-database.nixosModules.nix-index
#      niri.nixosModules.niri
#      ./system/cachix.nix
#    ];
#    system = "x86_64-linux";
#    createSystems = definitions:
#      mapAttrs (name: info:
#        nixpkgs.lib.nixosSystem {
#          inherit system;
#          specialArgs = {
#            inherit inputs outputs;
#            mainUser = info.user;
#          };
#          modules =
#            [
#              ./system/${name}.nix
#              home-manager.nixosModules.home-manager
#              {
#                home-manager = {
#                  useGlobalPkgs = true;
#                  extraSpecialArgs = {
#                    inherit inputs outputs;
#                    mainUser = info.user;
#                  };
#                  users.${info.user}.imports =
#                    [
#                      ./home/${info.user}.nix
#                    ]
#                    ++ info.hmImports or [];
#                };
#              }
#            ]
#            ++ info.imports or []
#            ++ sharedModules;
#        })
#      definitions;
#  in {
#    overlays = import ./util/overlay.nix {inherit inputs;};
#
#    nixosConfigurations = createSystems {
#      quiver.user = "bolt";
#      adrift.user = "plank";
#    };
#  };
#}
