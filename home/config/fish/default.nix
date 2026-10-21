{ self, pkgs, lib, ... }:
{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellAliases = lib.mkForce { }; # each `alias` call costs ~0.4ms at startup; ls/ll/l/wui are functions in home/config/fish
    shellInit = ''
      			set -g fish_greeting # disable greeting
      			source ${self}/home/config/fish/__main__.fish
    '';
  };
}
