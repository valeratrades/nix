{ pkgs, ... }:

{
	programs.fish = {
		enable = true;
		package = pkgs.fish;
		shellInit = ''
			source /etc/nixos/home/config/fish/main.fish
		'';
	};
}
