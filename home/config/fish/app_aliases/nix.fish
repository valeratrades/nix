alias flake-build="sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v"
#TODO!: make into a function and git-commit with $argv concatenation for message
alias nixup="git -C '$NIXOS_CONFIG' add -A && nix flake update --flake '$NIXOS_CONFIG' && sudo nixos-rebuild switch --show-trace -v --impure --fast && git_upload '$NIXOS_CONFIG'"
#TODO!: add git wrapper
alias nhup="nh os switch --hostname vlaptop '$NIXOS_CONFIG' -- --impure"
alias nshell="nix-shell --command fish"
alias ndevelop="nix develop --command fish"
#alias nupdate="nix flake lock --update-input nixpkgs --update-input"
alias nup="nix flake update"
alias up="$NIXOS_CONFIG/home/scripts/maintenance/main.sh"

function nsync
	if [ (whoami) == "v" ]
		echo "uhm?"
		return 1
	end
	git -C $NIXOS_CONFIG reset --hard && git -C $NIXOS_CONFIG pull && sudo nixos-rebuild switch --flake $NIXOS_CONFIG#$(hostname) --impure --no-reexec
end

function nb
	sudo nixos-rebuild switch --impure --no-reexec --flake ~/nix#$(hostname)
	if [ (count $argv) != 0 ]
		if [ $argv[1] = "-b" ] || [ $argv[1] = "--beep" ]
			beep "nix rb $status"
		end
		set hostName $argv[1]
	end
	return $status
end

function nbg
	set hostName (hostname)
	if [ (count $argv) = 1 ]
		set hostName $argv[1]
	end
	sudo nixos-rebuild switch --flake "github:valeratrades/nix#$hostName" --impure --no-reexec
end
