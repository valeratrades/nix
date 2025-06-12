function uv_bump
	uv sync --all-extras --dev --prerelease=allow && uv build && ggc "bump"
	beep
end
