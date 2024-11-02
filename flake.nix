{
	description = "OS master";

	#TODO!: setup my [own cache server](<https://nixos-and-flakes.thiscute.world/nix-store/host-your-own-binary-cache-server>). Needed to avoid rebuilding on lower-performance machines, like Rapsberri Pi
	nixConfig = {
		# extra means system-level
		extra-substituters = [
			# can add a local mirror with these
			#status: https://mirror.sjtu.edu.cn/
			#"https://mirror.sjtu.edu.cn/nix-channels/store"
			#status: https://mirrors.ustc.edu.cn/status/
			#"https://mirrors.ustc.edu.cn/nix-channels/store"

			"https://cache.nixos.org"
			"https://nix-community.cachix.org" # nix community's cache server
		];
		extra-trusted-public-keys = [
			"nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # nix community's cache server public key
		];
	};


	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
		nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";

		home-manager = {
			url = "github:nix-community/home-manager/master";
			# The `follows` keyword in inputs is used for inheritance.
			# Here, `inputs.nixpkgs` of home-manager is kept consistent with
			# the `inputs.nixpkgs` of the current flake,
			# to avoid problems caused by different versions of nixpkgs.
			inputs.nixpkgs.follows = "nixpkgs";
		};

		fenix = {
			url = "github:nix-community/fenix";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		#TODO!: integrate
		lanzaboote = {
			url = "github:nix-community/lanzaboote/v0.4.1";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		#TODO!: integrate
		impermanence.url = "github:nix-community/impermanence";

		pre-commit-hooks = {
			url = "github:cachix/pre-commit-hooks.nix";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		#inputs.sops-nix.url = "github:Mic92/sops-nix";


		#naersk.url = "https://github.com/nix-community/naersk/master";

		# -----------------------------------------------------------------
		# My packages
		# ----------------------------------------------------------------
		auto_redshift = {
			url = "github:valeratrades/auto_redshift";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		todo = {
			url = "github:valeratrades/todo";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		booktyping = {
			url = "github:valeratrades/booktyping";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		btc_line = {
			url = "github:valeratrades/btc_line";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		tg = {
			url = "github:valeratrades/tg";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		bbeats = {
			url = "github:valeratrades/bbeats";
			inputs.nixpkgs.follows = "nixpkgs";
		};	


		#aggr_orderbook = {
		#	url = "github:valeratrades/aggr_orderbook";
		#	inputs.nixpkgs.follows = "nixpkgs";
		#};
		#orderbook_3d = {
		#	url = "github:valeratrades/todo";
		#	inputs.nixpkgs.follows = "nixpkgs";
		#};

	};

	outputs = inputs@{ self, nixpkgs, nixpkgs-stable, home-manager, ... }: {
		# from https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system 
		#nix.registry.nixpkgs.flake = nixpkgs;
		#nix.channel.enable = false;
		#environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
		#nix.settings.nix-path = nixpkgs.lib.mkForce "nixpkgs=/etc/nix/inputs/nixpkgs";

		#NB: when writing hostname, remove all '_' characters
		nixosConfigurations.vlaptop = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";

			#environment.variables.NIXOS_CONFIG = "something";

			specialArgs = { 
				inherit inputs;
				inherit self;

				# freaks out on `inherit system`
				#pkgs-stable = import nixpkgs-stable {
				#	inherit system;
				#	config.allowUnfree = true;
				#};nixpkgs.legacyPackages.${system};
			};

			modules = [
				./os/configuration.nix
				./machines/modules/default.nix # can't reference the `mod.nix` one level higher, because I don't use `flake-parts.lib.mkFlake` yet

				home-manager.nixosModules.home-manager {
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;
					home-manager.backupFileExtension = "backup"; # delusional home-manager wants this exact file-extension for when I backup system-level files
					home-manager.extraSpecialArgs = { inherit inputs; inherit self; };

					#home-manager.sharedModules = [
					#	inputs.sops-nix.homeManagerModules.sops
					#];

					home-manager.users.v = import ./hosts/v_laptop/home.nix;
					nix.settings.trusted-users = [ "v" ];
				}

				({ pkgs, ... }: import ./modules/fenix.nix { inherit pkgs; })
			];
		};
	};
}
