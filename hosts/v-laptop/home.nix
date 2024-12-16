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
{
  #nix.extraOptions = "include ${config.home.homeDirectory}/s/g/private/sops.conf";
  #sops = {
  #	defaultSopsFile = "${config.home.homeDirectory}/s/g/private/sops.yaml";
  #};

  #defaultSopsFile = /home/v/s/g/private/sops.json;
  #defaultSopsFormat = "json";

  home = {
    packages =
      with pkgs;
      builtins.trace "DEBUG: sourcing Valera-specific home.nix" lib.lists.flatten [
        nyxt
        en-croissant # chess analysis GUI
        ncspot
        #flutterPackages-source.stable // errors
      ]

      ++ [
        # some of my own packages are in shared, not everything is here
        inputs.btc_line.packages.${pkgs.system}.default
        #inputs.prettify_log.packages.${pkgs.system}.default
        inputs.distributions.packages.${pkgs.system}.default # ? shared?
        inputs.bad_apple_rs.packages.${pkgs.system}.default

        #inputs.aggr_orderbook.packages.${pkgs.system}.default
        #inputs.orderbook_3d.packages.${pkgs.system}.default
      ];
  };
}
