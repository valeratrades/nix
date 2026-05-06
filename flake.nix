{
  description = "OS master";

  #TODO!: setup my [own cache server](<https://nixos-and-flakes.thiscute.world/nix-store/host-your-own-binary-cache-server>). Needed to avoid rebuilding on lower-performance machines, like Rapsberri Pi or old laptops.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/549bd84d6279f9852cae6225e372cc67fb91a4c1";
    rust-overlay.url = "github:oxalica/rust-overlay/adf987c76af8d17b8256d23631bcf203f81e1a63";
    flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";

    # pin to avoid rebuilds {
    pin-nixpkgs-ollama.url = "github:nixos/nixpkgs/e4bae1bd10c9c57b2cf517953ab70060a828ee6f";
    # }

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

    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay"; #TODO: switch back to stable once 12.0 is out

    disko = {
      url = "github:nix-community/disko/v1.9.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    haumea = {
      url = "github:nix-community/haumea/v0.2.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord = {
      url = "github:kaylorben/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    claude_code_nix.url = "github:sadjow/claude-code-nix";

    codex_nix.url = "github:sadjow/codex-cli-nix";

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # -----------------------------------------------------------------
    # My packages
    # ----------------------------------------------------------------
    auto_redshift = {
      url = "github:valeratrades/auto_redshift";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tedi = {
      url = "github:valeratrades/tedi";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    booktyping = {
      url = "github:valeratrades/booktyping";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    btc_line = {
      url = "github:valeratrades/btc_line/b8b410eb9d18a9e58fef054a7316aba23ee6f434";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    decant = {
      url = "github:valeratrades/decant";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    discretionary_engine = {
      url = "git+https://github.com/valeratrades/discretionary_engine?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    math_tools = {
      url = "github:valeratrades/math_tools";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    tg = {
      url = "github:valeratrades/tg"; #dbg: ?ref=release
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    bbeats = {
      url = "github:valeratrades/bbeats";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    book_parser = {
      url = "github:valeratrades/book_parser";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    prettify_log = {
      url = "github:valeratrades/prettify_log?ref=release";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    distributions = {
      url = "github:valeratrades/distributions";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    reasonable_envsubst = {
      url = "github:valeratrades/reasonable_envsubst";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bad_apple_rs = {
      url = "github:lomirus/bad-apple-rs"; # merged my nix-integration pull
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ask_llm = {
      url = "github:valeratrades/ask_llm?ref=release";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    translate_infrequent = {
      url = "github:valeratrades/translate_infrequent";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    cargo_sort_derives = {
      url = "github:valeratrades/cargo-sort-derives"; # TODO: switch to upstream once my PR is merged
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    wallpaper_carousel = {
      url = "github:valeratrades/wallpaper_carousel";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };
    snapshot_fonts = {
      url = "github:valeratrades/snapshot_fonts?ref=release";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
    };

    #aggr_orderbook = {
    #	url = "github:valeratrades/aggr_orderbook";
    #	inputs.nixpkgs.follows = "nixpkgs";
    #};

  };

  outputs = inputs: import ./outputs inputs;
}
