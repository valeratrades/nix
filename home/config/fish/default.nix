{ self, pkgs, ... }:

{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellInit = ''
			set -g fish_greeting # disable greeting
			source ${self}/home/config/fish/mod.fish
			mkdir -p $HOME/tmp # `-p` suppresses the warnings too apparently
			mkdir -p $HOME/Videos/obs
    '';
  };
}
