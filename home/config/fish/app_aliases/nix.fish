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
	set -l extra_flags ""
	set -l do_beep 0

	if test (count $argv) -gt 0
		if test $argv[1] = "-b" -o $argv[1] = "--beep"
			beep "nix rb"
			set do_beep 1
			set argv $argv[2..-1]
		end
	end

	if test (count $argv) -gt 0
		if test $argv[1] = "-D"
			set extra_flags "--show-trace --option --abort-on-warn true"
			set argv $argv[2..-1]
		end
	end

	sudo nixos-rebuild switch --impure --no-reexec --flake ~/nix#(hostname) $extra_flags
	set -l status_code $status

	if test $do_beep -eq 1
		beep "nix rb $status_code"
	end

	return $status_code
end


function nbg
	set hostName (hostname)
	if [ (count $argv) = 1 ]
		set hostName $argv[1]
	end
	sudo nixos-rebuild switch --flake "github:valeratrades/nix#$hostName" --impure --no-reexec
end
