function loop
    set -l file $argv[1]
    while true
        ffplay -nodisp -autoexit -loglevel quiet "$file"
    end
end
