{ pkgs, ... }:

{
	programs.fish = {
		enable = true;
		package = pkgs.fish;
		shellInit = ''
			source /etc/nixos/config/fish/main.fish
		'';
	};
}
