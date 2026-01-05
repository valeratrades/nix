alias dira="git add -A && direnv allow"
complete -c dira -w direnv
function dirw
	# direnv wrap
	direnv allow && \
	$argv && \
	direnv deny
end
complete -c dirw -w direnv
alias dirr="rm -r .direnv; dira" # for `direnv reload`
complete -c dirr -w direnv
alias dird="direnv deny"
complete -c dird -w direnv
