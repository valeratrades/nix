alias dira="git add -A && direnv allow"
function dirw
	# direnv wrap
	direnv allow && \
	$argv && \
	direnv deny
end
alias dirr="rm -r .direnv; dira" # for `direnv reload`
alias dird="direnv deny"
