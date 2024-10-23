function cut_videos
    printf "Use video-cut cli\n"
end

function concat_videos
    echo "file $argv[1]" > /tmp/filelist.txt
    echo "file $argv[2]" >> /tmp/filelist.txt

    ffmpeg -f concat -safe 0 -i /tmp/filelist.txt -c copy /tmp/output.mkv
    printf "Concatenated to: /tmp/output.mkv\n"
end
