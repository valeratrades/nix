inputs@{ self, nixpkgs, home-manager, pre-commit-hooks, ... }:
let
  inherit (inputs.nixpkgs) lib;
  #TODO!!: integrate ryan's myLib and myVars into my setup
  mylib = import ../lib { inherit lib; };
  myvars = import ../vars { inherit lib; };
  common_pkgs_config = {
    allowUnfree = true;
    allowBroken = true;
    permittedInsecurePackages =
      [ "electron-32.3.3" "ocaml5.3.0-virtual_dom-0.17.0" ];
    allowInsecurePredicate = pkg: true;
  };

  # Add my custom lib, vars, nixpkgs instance, and all the inputs to specialArgs,
  # so that I can use them in all my nixos/home-manager/darwin modules.
  genSpecialArgs = system:
    inputs // {
      inherit mylib myvars;

      pkgs-unstable = import inputs.nixpkgs-unstable {
        allowBroken = true;
        inherit
          system; # refer the `system` parameter form outer scope recursively
        # To use chrome, we need to allow the installation of non-free software
        config = common_pkgs_config;
      };
      pkgs-stable = import inputs.nixpkgs-stable {
        allowBroken = true;
        inherit system;
        # To use chrome, we need to allow the installation of non-free software
        config = common_pkgs_config;
      };
    };
  args = { inherit inputs lib mylib myvars genSpecialArgs; };

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

  forAllSystems = func:
    (nixpkgs.lib.genAttrs allSystemNames
      func); # NB: stolen from ryan, it's likely I'm misusing some part of this.
  user-vars = [ myvars.valera myvars.timur myvars.maria ];
in {
  # Add attribute sets into outputs, for debugging
  debugAttrs = {
    inherit nixosSystems darwinSystems allSystems allSystemNames;
  };

  # NixOS Hosts
  #nixosConfigurations =
  #  lib.attrsets.mergeAttrsList (map (it: it.nixosConfigurations or {}) nixosSystemValues);

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "electron-32.3.3" ];
    allowInsecurePredicate = pkg: true;
  };

  packages.x86_64-linux.wlr-gamma-service =
    inputs.nixpkgs-2405.legacyPackages.x86_64-linux.callPackage
    (builtins.fetchGit {
      url = "https://github.com/nobbz/wlr-brightness";
      rev = "1985062bf08086e6145db4ef1a292b535fd9f1a1";
      #sha256 = "sha256-QZhtI10qKu6qUePZ1rKaH3SBoUZ30+w8xcc5bBRYbGw=";
      #fetchSubmodules = true;
      submodules = true;
    }) { };
  #packages = forAllSystems (
  #   system: allSystems.${system}.packages or {}
  # );

  nixosConfigurations = lib.listToAttrs (map (user: {
    name = user.desktopHostName;
    value = nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs self;
        inherit mylib user;
      };

      modules = [
        (mylib.relativeToRoot "os/nixos/configuration.nix")
        (mylib.relativeToRoot "machines/modules/default.nix")

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension =
            "backup"; # delusional home-manager wants this exact file-extension for when I backup system-level files
          home-manager.extraSpecialArgs = {
            inherit inputs self;
            inherit mylib user;
          };

          home-manager.sharedModules = [
            inputs.nixcord.homeModules.nixcord
            inputs.sops-nix.homeManagerModules.sops
            inputs.tg.homeManagerModules.tg
            inputs.auto_redshift.homeManagerModules.auto_redshift
          ];

          home-manager.users."${user.username}" = import
            (mylib.relativeToRoot "hosts/${user.desktopHostName}/default.nix");
          nix.settings.trusted-users =
            [ user.username ]; # all systems assume single-user configurations
        }
      ];
    };
  }) user-vars);

  checks = forAllSystems (system: {
    #TODO!!: \
    #		# eval-tests per system
    #		eval-tests = allSystems.${system}.evalTests == {};
    #
    pre-commit-check = pre-commit-hooks.lib.${system}.run {
      src = mylib.relativeToRoot ".";
      hooks = {
        #TODO: the following shit does some weird weird fucking things, I need to once again find a good nix formatter
        #nixfmt-classic.enable = true; # seems to be the most reasonable (doesn't produce vertical bloat). But they change them way too often, fucking morons.

        #deadnix.enable = true; # detect unused variable bindings in `*.nix`. Also fails if false, so maybe this shouldn't be a hook.
        statix.enable =
          true; # lints and suggestions for Nix code(auto suggestions)
      };
    };
  });

  # Development Shells
  devShells = forAllSystems (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs;
          lib.lists.flatten [
            fish
            # fix `cc` replaced by clang, which causes nvim-treesitter compilation error
            gcc
            [
              # Nix-related
              #nixfmt-rfc-style
              nixpkgs-fmt
              deadnix
              statix
            ]
            typos # spell checker
            nodePackages.prettier # code formatter
          ];
        name = "dots";
        shellHook = ''
          ${self.checks.${system}.pre-commit-check.shellHook}
        '';
      };
    });

  formatter =
    forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
}
