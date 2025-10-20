{ self, pkgs, ... }:
{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellInit = ''
      			set -g fish_greeting # disable greeting
      			source ${self}/home/config/fish/mod.fish
    '';
  };
}
