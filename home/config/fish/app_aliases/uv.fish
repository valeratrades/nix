function uv_bump
    uv sync --all-extras --dev --prerelease=allow && uv build && ggc "bump"
    set code $status
    if test $code -eq 0
        sleep 0.05
        if test (count $argv) -gt 0
            git tag -f $argv[1]
            git push --tags
        end
    end
    beep -q
end

