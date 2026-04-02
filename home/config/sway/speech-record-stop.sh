#!/usr/bin/env bash
# speech-record-stop.sh — stop recording, transcribe, type result
export PATH="$HOME/.nix-profile/bin:$PATH"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
# Triggered on spacebar release while in speech mode.

LOG=/tmp/stt.log
echo "[$(date -Is)] stop script triggered" >> "$LOG"

AUDIO=/tmp/speech_rec.wav
PID_FILE=/tmp/speech_rec.pid
DRIVER_FILE=/tmp/speech_stt_driver
MODEL_DIR=$HOME/.local/share/whisper-cpp/models

# Stop recording
if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

# Give arecord a moment to flush/close the file
sleep 0.3

if [ ! -f "$AUDIO" ] || [ ! -s "$AUDIO" ]; then
    echo "[$(date -Is)] no audio file" >> "$LOG"
    notify-send -t 2000 "🎤 Speech STT" "No audio captured"
    exit 0
fi

echo "[$(date -Is)] audio size: $(stat -c%s "$AUDIO") bytes" >> "$LOG"

DRIVER=$(cat "$DRIVER_FILE" 2>/dev/null || echo "whisper")
echo "[$(date -Is)] driver: $DRIVER" >> "$LOG"
notify-send -t 6000 -u low "🔄 Transcribing..." "driver: $DRIVER"

TEXT=""

if [ "$DRIVER" = "whisper" ]; then
    MODEL="$MODEL_DIR/ggml-base.en.bin"

    if [ ! -f "$MODEL" ]; then
        mkdir -p "$MODEL_DIR"
        notify-send -t 15000 "🎤 Speech STT" "Downloading whisper base.en model (~150MB)..."
        whisper-cpp-download-ggml-model base.en "$MODEL_DIR"
    fi

    TEXT=$(whisper-cli -m "$MODEL" -f "$AUDIO" -np -nt 2>>"$LOG" \
        | sed 's/^\s*//' | tr -d '\n')

else
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        OPENAI_API_KEY=$(grep -Po 'set openaikey "\K[^"]+' "$HOME/s/g/private/credentials.fish" 2>/dev/null || true)
    fi

    RESP=$(curl -sf "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -F "file=@${AUDIO}" \
        -F "model=gpt-4o-transcribe" \
        -F "language=en" 2>>"$LOG")
    echo "[$(date -Is)] api response: $RESP" >> "$LOG"
    TEXT=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('text',''), end='')" 2>>"$LOG" || true)
fi

echo "[$(date -Is)] transcribed: '$TEXT'" >> "$LOG"

# Clean up audio file
rm -f "$AUDIO"

# Type the result into the focused window
if [ -n "$TEXT" ]; then
    wtype "$TEXT" 2>>"$LOG" || notify-send -t 3000 "🎤 STT" "wtype failed — check /tmp/stt.log"
else
    notify-send -t 2000 "🎤 Speech STT" "No transcription result"
fi
