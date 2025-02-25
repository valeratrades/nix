#TODO!: move much of this to shared dirs
{
  self,
  config,
  lib,
  pkgs,
  inputs,
  mylib,
  user,
  ...
}:
let
  sshConfigPath = "${config.home.homeDirectory}/.ssh";
in
{
  nix.extraOptions = "!include ${config.home.homeDirectory}/s/g/private/sops/";
  # ref: https://www.youtube.com/watch?v=G5f6GC7SnhU
  sops = {
    age.sshKeyPaths = [ "${sshConfigPath}/id_ed25519" ];
    defaultSopsFile = "${self}/secrets/users/v/default.json";
    defaultSopsFormat = "json";
    secrets.telegram_token_main = {
      mode = "0400";
    };
    secrets.telegram_token_test = {
      mode = "0400";
    };
  };

  tg-server = {
    enable = true;
    package = inputs.tg.packages.${pkgs.system}.default;
    token = config.sops.secrets.telegram_token_main.path;
  };

  home = {
    packages =
      with pkgs;
      builtins.trace "DEBUG: sourcing Valera-specific home.nix" lib.lists.flatten [
        nyxt
        chromium
        en-croissant # chess analysis GUI
        ncspot
        gitui

        libinput
        #flutterPackages-source.stable // errors

        virt-viewer
      ]

      ++ [
        # some of my own packages are in shared, not everything is here
        inputs.btc_line.packages.${pkgs.system}.default
        inputs.prettify_log.packages.${pkgs.system}.default
        inputs.distributions.packages.${pkgs.system}.default # ? shared?
        inputs.rm_engine.packages.${pkgs.system}.default
        inputs.bad_apple_rs.packages.${pkgs.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.system}.default
        #inputs.orderbook_3d.packages.${pkgs.system}.default
      ];
  };
}
