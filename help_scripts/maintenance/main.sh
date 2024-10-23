#!/bin/sh

sync()  {
	("$HOME/.dots/main.sh" sync "$@" && printf "\033[32msynced dots\033[0m\n" || printf "\033[34mremote repository is up to date\033[0m\n") &
	PID1=$!

	("$HOME/s/help_scripts/maintenance/clean_old_build_artefacts.sh" && printf "\033[32mChecked for old bulid artefacts\033[0m\n" || printf "\033[31mFailed to check for old build artefacts\033[0m\n") &
	PID2=$!

	("$HOME/s/help_scripts/maintenance/check_caches.sh" && printf "\033[32mChecked caches\033[0m\n" || printf "\033[31mFailed to check caches\033[0m\n") &
	PID3=$!

	#(sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak && sudo sh -c "rankmirrors -n 10 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist" && printf "\033[32mupdated mirrors\033[0m\n" || printf "\033[31mupdating mirrors failed\033[0m\n") &
	#PID4=$!

	wait $PID1 $PID2 $PID3
	# pacman operations are already parallelized
	#(sudo pacman -Syu --noconfirm && printf "\033[32mupdated system\033[0m\n") || (printf "\033[31mpacman -Syu failed. FIXME.\033[0m\n" && return 1)
	#
	## nix operations are already parallelized
	#(nix-env --upgrade && printf "\033[32mupdated nix\033[0m\n") || (printf "\033[31mnix-env --upgrade failed. FIXME.\033[0m\n" && return 1)

	sudo nixos-rebuild switch --impure
	return 0
}

sync "$@"
