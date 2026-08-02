alias dira="git add -A && direnv allow"
complete -c dira -w direnv
function dirw
	# direnv wrap
	direnv allow && \
	$argv && \
	direnv deny
end
complete -c dirw -w direnv
# manual reload: with global _nix_direnv_manual_reload this is THE way to update an env.
# nix-direnv-reload force-rebuilds in place (keeps gcroots); nuking .direnv is the fallback.
# _nix_direnv_force_reload only suppresses the manual-reload *warning*; it's read inside
# `if cache_invalid`, so a cache that merely looks fresh by mtime is never rebuilt. And
# _nix_refresh_gcroots touches flake-profile-* (incl. the .rc) on every cache hit, so
# "looks fresh" is the steady state. Deleting the rc is what actually forces the rebuild.
function dirr
	git add -A
	if test -x .direnv/bin/nix-direnv-reload
		find .direnv -maxdepth 1 -name '*-profile-*.rc' -delete
		.direnv/bin/nix-direnv-reload
	else
		rm -rf .direnv
		direnv allow
	end
end
complete -c dirr -w direnv
alias dird="direnv deny"
complete -c dird -w direnv
