{ self, pkgs, ... }:
{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellInit = ''
			set -g fish_greeting # disable greeting
			source ${self}/home/config/fish/mod.fish

			# moved these to home.nix. TODO: deprecate in a month (2024/11/29)
			#mkdir -p $HOME/tmp # `-p` suppresses the warnings too apparently
			#mkdir -p $HOME/Videos/obs
    '';
  };
}
