
cut_videos() {
	printf "Use video-cut cli\n"
}

concat_videos() {
	echo "file ${1}" > /tmp/filelist.txt
	echo "file ${2}" >> /tmp/filelist.txt

	ffmpeg -f concat -safe 0 -i filelist.txt -c copy /tmp/output.mkv
	pprint "Concatinated to: /tmp/output.mkv\n"
}
