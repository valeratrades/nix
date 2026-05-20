#!/usr/bin/env fish
# Tests whether audio played through the default sink actually reaches the
# `obs_virtual_mic` PipeWire source. Each test plays a known sound, records
# from obs_virtual_mic in parallel, then computes RMS dB. >-60 dB = PASS.
#
# Modes:
#   vmic_test                  — runs the full automated battery
#   vmic_test capture [SECS]   — opens a capture window (default 10s).
#                                Play whatever you want during it (YouTube
#                                in your real browser, etc.) and get a verdict.
#
# Designed to need zero interaction beyond invocation. No phone, no headphones,
# no meeting required.

set __dir (dirname (status --current-filename))
set NOTIFICATION_44K $__dir/assets/sound/Notification.mp3
set TMP_DIR (mktemp -d -t vmic-test.XXXXXX)
set NOTIFICATION_48K $TMP_DIR/notification-48k.mp3

set RMS_PASS_THRESHOLD_DB -60

function _cleanup --on-event fish_exit
	rm -rf $TMP_DIR
end

function _have_virtual_mic
	pactl list sources short 2>/dev/null | grep -q '^[0-9]\+	obs_virtual_mic	'
end

function _obs_running
	# OBS binary's `comm` is `.obs-wrapped` on this nix-wrapped install,
	# not `obs`. Match via argv0 ("obs" or ".obs-wrapped") which pgrep -f sees.
	pgrep -f '(^|/)\.?obs(-wrapped)?($| )' >/dev/null 2>&1
end

function _obs_writes_to_vmic
	# Is OBS's monitor bus actually wired to obs-virtual-mic?
	# `pw-link -lo` lists each output port on its own line, followed by
	# `  |-> target` indented lines per connection. We need OBS-Monitor's
	# children to include obs-virtual-mic:playback.
	pw-link -lo 2>/dev/null | grep -A1 '^OBS-Monitor:output' \
		| grep -q 'obs-virtual-mic:playback'
end

function _rms_db --argument-names wav
	# Parse "Overall.RMS_level" out of ffmpeg's astats filter.
	# Returns the dB as a string; "-inf" on silence; "ERR" if parsing fails.
	set out (ffmpeg -hide_banner -nostats -i $wav -af astats=metadata=1 \
		-f null - 2>&1 | string match -rg 'Overall\s+\S+\s*\n.*?RMS level dB:\s*(\S+)')
	if test -z "$out"
		# fallback: any RMS level dB line
		set out (ffmpeg -hide_banner -nostats -i $wav -af astats=metadata=1 \
			-f null - 2>&1 | string match -rg 'RMS level dB:\s*(\S+)' | tail -1)
	end
	if test -z "$out"
		echo "ERR"
	else
		echo $out
	end
end

function _pass_fail --argument-names rms_db
	if test "$rms_db" = "ERR"; echo "ERR"; return; end
	if test "$rms_db" = "-inf"; echo "FAIL"; return; end
	# Numeric compare. fish `math` doesn't support `>`, use awk for float cmp.
	if string match -rq '^-?[0-9]+(\.[0-9]+)?$' -- $rms_db
		if awk -v a=$rms_db -v b=$RMS_PASS_THRESHOLD_DB 'BEGIN{exit !(a>b)}'
			echo "PASS"
		else
			echo "FAIL"
		end
	else
		echo "ERR"
	end
end

function _capture --argument-names duration_s out_wav
	# Records `duration_s` seconds from obs_virtual_mic into `out_wav` (s16le 48k stereo).
	# Synchronous: returns when capture is done.
	# NOTE: parecord on this system ignores SIGINT; must use SIGTERM, with
	# SIGKILL fallback. SIGINT + wait hangs forever.
	parecord --device=obs_virtual_mic --rate=48000 --channels=2 \
		--format=s16le --file-format=wav $out_wav >/dev/null 2>&1 &
	set -l pid $last_pid
	sleep $duration_s
	kill $pid 2>/dev/null
	sleep 0.2
	kill -KILL $pid 2>/dev/null
	wait $pid 2>/dev/null
end

function _run_test
	# usage: _run_test <name> <duration_s> <player_argv...>
	set -l name $argv[1]
	set -l dur  $argv[2]
	set -l player_cmd $argv[3..-1]
	set -l wav $TMP_DIR/test-(echo $name | tr / _).wav

	# Start listener first so we don't miss the player's opening samples.
	parecord --device=obs_virtual_mic --rate=48000 --channels=2 \
		--format=s16le --file-format=wav $wav >/dev/null 2>&1 &
	set -l lpid $last_pid
	sleep 0.4

	# Start player in background.
	$player_cmd >/dev/null 2>&1 &
	set -l ppid $last_pid

	sleep $dur

	kill $ppid 2>/dev/null
	kill $lpid 2>/dev/null
	sleep 0.2
	kill -KILL $lpid 2>/dev/null
	wait $ppid 2>/dev/null
	wait $lpid 2>/dev/null

	set -l rms (_rms_db $wav)
	set -l verdict (_pass_fail $rms)
	printf "  %-22s  RMS=%-8s  %s\n" $name $rms $verdict
end

# -----------------------------------------------------------------------------

if not _have_virtual_mic
	echo "vmic_test: obs_virtual_mic source not present in PipeWire." >&2
	echo "  Is the null-sink config loaded? Check:" >&2
	echo "    pactl list sources short | grep virtual" >&2
	exit 1
end

if not _obs_running
	echo "vmic_test: OBS is not running." >&2
	echo "  The virtual mic gets its content from OBS's monitor bus." >&2
	echo "  Without OBS, every test will return -inf dB. Start OBS first." >&2
	exit 1
end

if not _obs_writes_to_vmic
	echo "vmic_test: WARNING — OBS is running but its monitor output is not" >&2
	echo "  linked to obs-virtual-mic. Set:" >&2
	echo "    OBS → Settings → Audio → Monitoring Device = OBS Virtual Mic" >&2
	echo "  and per-source set Audio Monitoring = 'Monitor and Output'." >&2
	echo "  Continuing anyway, but expect FAILs." >&2
	echo >&2
end

# Capture-only mode: just record what comes in over the next N seconds.
if test (count $argv) -ge 1; and test "$argv[1]" = "capture"
	set -l dur 10
	if test (count $argv) -ge 2; set dur $argv[2]; end
	set -l wav $TMP_DIR/capture.wav
	echo "Capturing from obs_virtual_mic for $dur seconds."
	echo "Play whatever you want now (YouTube, meet test page, etc.)."
	_capture $dur $wav
	set -l rms (_rms_db $wav)
	set -l verdict (_pass_fail $rms)
	echo
	printf "Result: RMS=%s  %s\n" $rms $verdict
	if test "$verdict" = "PASS"
		echo "Saved capture: $wav (will be deleted on shell exit)"
		# Persist a copy so user can inspect waveform/spectrum afterwards:
		cp $wav /tmp/vmic-capture.wav
		echo "Persistent copy: /tmp/vmic-capture.wav  (audacity-friendly)"
	end
	exit 0
end

# Automated battery.
echo "=== vmic_test: virtual mic audio routing battery ==="
echo "Listener: obs_virtual_mic. Threshold: RMS > $RMS_PASS_THRESHOLD_DB dB = PASS."
echo

# Precompute a 48k transcoded notification so we can isolate sample-rate effects.
ffmpeg -hide_banner -loglevel error -y -i $NOTIFICATION_44K -ar 48000 \
	$NOTIFICATION_48K
or begin
	echo "vmic_test: failed to transcode notification to 48k. Aborting." >&2
	exit 2
end

# Tests are ordered to probe specific hypotheses:
#   burst-* : short-lived stream (ffplay opens, writes, closes). Lifecycle = brief.
#   loop-*  : continuous, multi-second stream. Lifecycle = long, more time for
#             monitor-bus drift to accumulate.
#   *-44k / *-48k : control for sample rate hypothesis (Notification.mp3 is 44.1k).
echo "Lifecycle tests (player opens / closes quickly):"
_run_test "burst-44k"   3 ffplay -nodisp -autoexit -loglevel quiet $NOTIFICATION_44K
_run_test "burst-48k"   3 ffplay -nodisp -autoexit -loglevel quiet $NOTIFICATION_48K
echo
echo "Continuous-stream tests (player runs for full duration):"
_run_test "loop-44k"    6 ffplay -nodisp -autoexit -loglevel quiet -loop 5 $NOTIFICATION_44K
_run_test "loop-48k"    6 ffplay -nodisp -autoexit -loglevel quiet -loop 5 $NOTIFICATION_48K
echo
echo "Browser test must be run manually:"
echo "    vmic_test capture 10"
echo "  then play YouTube in your real browser within the 10s window."
