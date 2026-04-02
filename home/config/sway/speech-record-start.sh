#!/usr/bin/env bash
# speech-record-start.sh — start recording audio for STT
export PATH="$HOME/.nix-profile/bin:$PATH"
# Triggered on spacebar press while in speech mode.

LOG=/tmp/stt.log
echo "[$(date -Is)] start script triggered" >> "$LOG"

AUDIO=/tmp/speech_rec.wav
PID_FILE=/tmp/speech_rec.pid

# Kill any stale recording process
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
fi
rm -f "$AUDIO"

# Start recording: 16kHz mono WAV (optimal for whisper)
arecord -r 16000 -c 1 -f S16_LE -t wav "$AUDIO" 2>>"$LOG" &
echo $! > "$PID_FILE"
echo "[$(date -Is)] recording started, pid=$(cat $PID_FILE)" >> "$LOG"
