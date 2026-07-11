alias n="nix"
complete -c n -w nix

# `nix develop`: fully offline when the env is already realized locally; online only
# when something is genuinely missing. The probe realizes the same env, so the offline
# develop after it is instant. --max-jobs 0 makes the probe fail fast instead of
# silently source-building GC'd deps. A genuine eval error gets evaluated twice (cheap).
# See ongoing_debug/2026-07-11_nix-develop-direnv-offline.md
function nix --wraps nix
	if test "$argv[1]" = develop
		# --command/-c consumes everything after it; strip for the probe
		set -l probe_args
		for a in $argv[2..]
			if contains -- $a --command -c
				break
			end
			set -a probe_args $a
		end
		if command nix print-dev-env --offline --max-jobs 0 $probe_args &>/dev/null
			command nix develop --offline $argv[2..]
		else
			command nix $argv
		end
	else
		command nix $argv
	end
end
alias flake-build="sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v"
#TODO!: make into a function and git-commit with $argv concatenation for message
alias nixup="git -C '$NIXOS_CONFIG' add -A && nix flake update --flake '$NIXOS_CONFIG' && sudo nixos-rebuild switch --show-trace -v --impure --fast && git_upload '$NIXOS_CONFIG'"
#TODO!: add git wrapper
alias nhup="nh os switch --hostname vlaptop '$NIXOS_CONFIG' -- --impure"
alias nshell="nix-shell --command fish"
alias ndevelop="nix develop --command fish"
#alias nupdate="nix flake lock --update-input nixpkgs --update-input"
alias nup="nix flake update"
alias up="$NIXOS_CONFIG/home/scripts/maintenance.rs"

function nsync
	if [ (whoami) == "v" ]
		echo "uhm?"
		return 1
	end
	git -C $NIXOS_CONFIG reset --hard && git -C $NIXOS_CONFIG pull && sudo nixos-rebuild switch --flake $NIXOS_CONFIG#$(hostname) --impure --no-reexec
end


function nbg
	set hostName (hostname)
	if [ (count $argv) = 1 ]
		set hostName $argv[1]
	end
	sudo nixos-rebuild switch --flake "github:valeratrades/nix#$hostName" --impure --no-reexec
end
