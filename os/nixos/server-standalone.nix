#TODO!!!: integrate with the rest of the config. Atm I just have this head on the server, and some other stuff set up by hand
{ config, pkgs, ... }:
let
  user = "nixos";
in
{
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal-combined.nix> ];
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "electron-32.3.3" ];
    allowInsecurePredicate = pkg: true;
  };
  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    package = pkgs.direnv;
    nix-direnv = {
      enable = true; # faster on nix
      package = pkgs.nix-direnv;
    };
    silent = true;
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."valeratrades.com" = {
      #forceSSL = true; # redirects http -> https
      #enableACME = true; # automatically get a Let's Encrypt certificate #TODO: .
      enableACME = false;
      serverAliases = [ "www.valeratrades.com" ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:61156";
      };
    };
  };

  users.users."${user}" = {
    extraGroups = [
      "networkmanager"
      "wheel"
      "keyd"
      "audio"
      "video"
      "docker"
      "dialout"
      "postgres"
    ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true; # Q: can I have this be powershell?

  #TODO: setup email with @valeratrades, then this \
  #	security.acme = {
  #  acceptTerms = true;
  #  defaults.email = "valeratrades@gmail.com";
  #};
  #
  #services.nginx.virtualHosts."valeratrades.com".enableACME = true;
  #services.nginx.virtualHosts."valeratrades.com".forceSSL = true;

  environment.systemPackages = with pkgs; [
    neovim
    vscode
    nginx
    gsettings-desktop-schemas
    air
    go
    glib
    tmux
    powershell # for shit and giggles
    atuin
    starship
    fish
    dig
    perl
    rustup
    nil
    whois
    niv # nix build dep management
    nix-diff
    statix # Lints and suggestions for the nix programming language
    deadnix # Find and remove unused code in .nix source files
    nix-direnv
    gcc
  ];
}
