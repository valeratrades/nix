{ pkgs, ... }:

{
	programs.fish = {
		enable = true;
		package = pkgs.fish;
		shellInit = ''
			source "$HOME/.config/fish/main.fish"
		'';
	};
}

