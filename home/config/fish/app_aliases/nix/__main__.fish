function n --wraps nix; nix $argv; end

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
function flake-build --wraps 'sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v'; sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v $argv; end
#TODO!: make into a function and git-commit with $argv concatenation for message
function nixup; git -C $NIXOS_CONFIG add -A && nix flake update --flake $NIXOS_CONFIG && sudo nixos-rebuild switch --show-trace -v --impure --fast && git_upload $NIXOS_CONFIG $argv; end
#TODO!: add git wrapper
function nhup; nh os switch --hostname vlaptop $NIXOS_CONFIG -- --impure $argv; end
function nshell --wraps 'nix-shell --command fish'; nix-shell --command fish $argv; end
function ndevelop --wraps 'nix develop --command fish'; nix develop --command fish $argv; end
#alias nupdate="nix flake lock --update-input nixpkgs --update-input"
function nup --wraps 'nix flake update'; nix flake update $argv; end
function up; $NIXOS_CONFIG/home/scripts/maintenance.rs $argv; end
function typst_workspace; $NIXOS_CONFIG/home/scripts/typst_workspace.rs $argv; end
function tw --wraps typst_workspace; typst_workspace $argv; end

function nsync
	if [ (whoami) == "v" ]
		echo "uhm?"
		return 1
	end
	git -C $NIXOS_CONFIG reset --hard && git -C $NIXOS_CONFIG pull && sudo nixos-rebuild switch --flake "$NIXOS_CONFIG?submodules=1#$(hostname)" --impure --no-reexec
end


function nbg
	set hostName (hostname)
	if [ (count $argv) = 1 ]
		set hostName $argv[1]
	end
	sudo nixos-rebuild switch --flake "github:valeratrades/nix#$hostName" --impure --no-reexec
end
