function uv_bump
	uv sync --all-extras --dev --prerelease=allow && uv build && ggc "bump" \
		&& test (count $argv) -gt 0 && git tag -f $argv[1] && git push --tags
	beep -q
end
