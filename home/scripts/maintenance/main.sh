#!/bin/sh

dot="$(dirname "$0")"

sync()  {
	#("$HOME/.dots/main.sh" sync "$@" && printf "\033[32msynced dots\033[0m\n" || printf "\033[34mremote repository is up to date\033[0m\n") &
	#PID1=$!

	("$dot/clean_old_build_artefacts.sh" && printf "\033[32mChecked for old bulid artefacts\033[0m\n" || printf "\033[31mFailed to check for old build artefacts\033[0m\n") &
	PID2=$!

	("$dot/check_caches.sh" && printf "\033[32mChecked caches\033[0m\n" || printf "\033[31mFailed to check caches\033[0m\n") &
	PID3=$!

	(fish -c "check_nightly_versions --discover" && printf "\033[32mRefreshed nightly version file cache\033[0m\n" || printf "\033[31mFailed to refresh nightly version cache\033[0m\n") &
	PID4=$!

	wait $PID2 $PID3 $PID4 #$PID1

	sudo nixos-rebuild switch --show-trace -v --impure && git -C "$NIXOS_CONFIG" add -A && git -C "$NIXOS_CONFIG" commit -m "_" && git -C "$NIXOS_CONFIG" push  # git commit nix files only on successful build
	return 0
}

sync "$@"
