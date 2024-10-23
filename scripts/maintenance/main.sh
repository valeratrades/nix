#!/bin/sh

sync()  {
	("$HOME/.dots/main.sh" sync "$@" && printf "\033[32msynced dots\033[0m\n" || printf "\033[34mremote repository is up to date\033[0m\n") &
	PID1=$!

	("$HOME/s/help_scripts/maintenance/clean_old_build_artefacts.sh" && printf "\033[32mChecked for old bulid artefacts\033[0m\n" || printf "\033[31mFailed to check for old build artefacts\033[0m\n") &
	PID2=$!

	("$HOME/s/help_scripts/maintenance/check_caches.sh" && printf "\033[32mChecked caches\033[0m\n" || printf "\033[31mFailed to check caches\033[0m\n") &
	PID3=$!

	wait $PID1 $PID2 $PID3

	nixos_root="/etc/nixos"
	sudo nixos-rebuild switch --show-trace -L -v --impure && git -C "$nixos_root" add -A && git -C "$nixos_root" commit -m "_" && git -C "$nixos_root" push  # git commit nix files only on successful build
	return 0
}

sync "$@"
