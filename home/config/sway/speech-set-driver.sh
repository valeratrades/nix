#!/usr/bin/env bash
# speech-set-driver.sh — set the active STT driver
# Usage: speech-set-driver.sh [whisper|gpt4o]
DRIVER="${1:-whisper}"
echo "$DRIVER" > /tmp/speech_stt_driver
notify-send -t 1500 "🎤 Speech STT" "Driver: $DRIVER"
