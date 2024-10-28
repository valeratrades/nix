{ pkgs, ... }:

{
  programs.fish = {
    enable = true;
    package = pkgs.fish;
    shellInit = ''
			set -g fish_greeting # disable greeting
			source /etc/nixos/home/config/fish/mod.fish

			# jumping through hoops because of [dbus-daemon issue](<https://github.com/NixOS/nixpkgs/issues/308771>)
			if not test -f /tmp/sway_has_been_started.status
				touch /tmp/sway_has_been_started.status
				sway
			end
		'';
  };
}
