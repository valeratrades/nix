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
function dirr
	git add -A
	if test -x .direnv/bin/nix-direnv-reload
		.direnv/bin/nix-direnv-reload
	else
		rm -rf .direnv
		direnv allow
	end
end
complete -c dirr -w direnv
alias dird="direnv deny"
complete -c dird -w direnv
