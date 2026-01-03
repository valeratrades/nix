{
  description = "OS master";

  #TODO!: setup my [own cache server](<https://nixos-and-flakes.thiscute.world/nix-store/host-your-own-binary-cache-server>). Needed to avoid rebuilding on lower-performance machines, like Rapsberri Pi or old laptops.

  inputs = {
    nixpkgs = {
      #url = "github:nixos/nixpkgs/nixos-24.11"; #unstable";
      url =
        "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #TODO!: integrate
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";

    disko = {
      url = "github:nix-community/disko/v1.9.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord.url = "github:kaylorben/nixcord";

    sops-nix.url = "github:Mic92/sops-nix";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # -----------------------------------------------------------------
    # My packages
    # ----------------------------------------------------------------
    auto_redshift = {
      url = "github:valeratrades/auto_redshift";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    todo.url = "github:valeratrades/todo?ref=release";
    booktyping = {
      url = "github:valeratrades/booktyping";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    btc_line = {
      url = "github:valeratrades/btc_line?ref=release";
    };
    discretionary_engine = {
      url = "git+https://github.com/valeratrades/discretionary_engine?submodules=1";
    };
    math_tools = { url = "github:valeratrades/math_tools"; };
    tg.url = "github:valeratrades/tg?ref=release";
    bbeats = {
      url = "github:valeratrades/bbeats";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    book_parser = {
      url = "github:valeratrades/book_parser";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    prettify_log.url = "github:valeratrades/prettify_log?ref=release";
    distributions = {
      url = "github:valeratrades/distributions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    reasonable_envsubst = {
      url = "github:valeratrades/reasonable_envsubst";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bad_apple_rs = {
      url = "github:lomirus/bad-apple-rs"; # merged my nix-integration pull
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ask_llm.url = "github:valeratrades/ask_llm?ref=release";
    translate_infrequent.url = "github:valeratrades/translate_infrequent";
    cargo_sort_derives.url =
      "github:valeratrades/cargo-sort-derives"; # TODO: switch to upstream once my PR is merged

    wallpaper_carousel.url = "github:valeratrades/wallpaper_carousel";
    snapshot_fonts.url = "github:valeratrades/snapshot_fonts?ref=release";

    #aggr_orderbook = {
    #	url = "github:valeratrades/aggr_orderbook";
    #	inputs.nixpkgs.follows = "nixpkgs";
    #};
    #orderbook_3d = {
    #	url = "github:valeratrades/todo";
    #	inputs.nixpkgs.follows = "nixpkgs";
    #};

  };

  outputs = inputs: import ./outputs inputs;
}
