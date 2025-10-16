{
  description = "OS master";

  #TODO!: setup my [own cache server](<https://nixos-and-flakes.thiscute.world/nix-store/host-your-own-binary-cache-server>). Needed to avoid rebuilding on lower-performance machines, like Rapsberri Pi
  #nixConfig = {
  #  # extra means system-level
  #  extra-substituters = [
  #    # can add a local mirror with these
  #    #status: https://mirror.sjtu.edu.cn/
  #    #"https://mirror.sjtu.edu.cn/nix-channels/store"
  #    #status: https://mirrors.ustc.edu.cn/status/
  #    #"https://mirrors.ustc.edu.cn/nix-channels/store"
  #
  #    "https://cache.nixos.org"
  #    "https://nix-community.cachix.org" # nix community's cache server
  #  ];
  #  extra-trusted-public-keys = [
  #    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # nix community's cache server public key
  #    "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s="
  #  ];
  #};

  inputs = {
    nixpkgs = {
      #url = "github:nixos/nixpkgs/nixos-24.11"; #unstable";
      url =
        "github:nixos/nixpkgs/nixos-unstable"; # TODO!!!!: switch to stable (last try it just broke some packages with indescernable errors)
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

    # doing rustup instead now
    #fenix = {
    #	url = "github:nix-community/fenix";
    #	inputs.nixpkgs.follows = "nixpkgs";
    #};

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
      url = "github:valeratrades/btc_line?ref=release";
      #inputs.nixpkgs.follows = "nixpkgs";
    };
    rm_engine = { url = "github:valeratrades/rm_engine?ref=release"; };
    tg = {
      url = "github:valeratrades/tg?ref=release";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bbeats = {
      url = "github:valeratrades/bbeats";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    prettify_log.url = "github:valeratrades/prettify_log";
    distributions = {
      url = "github:valeratrades/distributions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    reasonable_envsubst = {
      url = "github:valeratrades/reasonable_envsubst";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bad_apple_rs = {
      #url = "github:valeratrades/bad-apple-rs";
      url = "github:lomirus/bad-apple-rs"; # merged my nix-integration pull
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ask_llm.url = "github:valeratrades/ask_llm?ref=release";
    translate_infrequent.url = "github:valeratrades/translate_infrequent";
    cargo_sort_derives.url =
      "github:valeratrades/cargo-sort-derives"; # TODO: switch to upstream once my PR is merged

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
