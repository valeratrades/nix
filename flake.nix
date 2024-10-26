{
	description = "OS master";

	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
		nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";

		home-manager = {
			url = "github:nix-community/home-manager/release-24.05";
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

		lanzaboote = {
			url = "github:nix-community/lanzaboote/v0.4.1";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		impermanence.url = "github:nix-community/impermanence";

		pre-commit-hooks = {
			url = "github:cachix/pre-commit-hooks.nix";
			inputs.nixpkgs.follows = "nixpkgs";
		};


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

			specialArgs = { 
				inherit inputs;

				# freaks out on `inherit system`
				#pkgs-stable = import nixpkgs-stable {
				#	inherit system;
				#	config.allowUnfree = true;
				#};ixpkgs.legacyPackages.${system};
			};

			modules = [
				./os/configuration.nix

				home-manager.nixosModules.home-manager {
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;
					home-manager.backupFileExtension = "hm-backup";
					home-manager.extraSpecialArgs = { inherit inputs; };

					home-manager.users.v = import ./hosts/v_laptop/home.nix;
				}

				#./fenix.nix
				({ pkgs, ... }: import ./modules/fenix.nix { inherit pkgs; })

			];
		};
	};
}
