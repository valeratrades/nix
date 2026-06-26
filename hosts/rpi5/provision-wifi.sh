#!/usr/bin/env bash
# Write the wifi secret onto a freshly-flashed rpi5 SD card.
#
# Source of truth is sops (secrets/users/v/default.json: wifi_home_name,
# wifi_home_pass). This decrypts them on the trusted laptop and writes
# /var/lib/wifi.env onto the card's root partition — the ONLY place the wifi
# secret ever lives (never in the repo or nix store). NetworkManager's
# ensure-profiles service reads that file at boot (envsubst on $WIFI_SSID /
# $WIFI_PSK), so the Pi joins wifi on first plug-in.
#
# Idempotent. Usage: ./provision-wifi.sh [DEVICE]   (DEVICE default: /dev/sda)
set -euo pipefail

DEV="${1:-/dev/sda}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$HERE/../../secrets/users/v/default.json"

# Safety: refuse anything that isn't a USB disk carrying a flashed rpi card.
[[ -b "$DEV" ]] || { echo "error: $DEV is not a block device" >&2; exit 1; }
[[ "$(lsblk -dno TRAN "$DEV")" == "usb" ]] || { echo "error: $DEV is not USB — refusing (won't touch internal disks)" >&2; exit 1; }
ROOT_PART="$(lsblk -rno PATH,LABEL "$DEV" | awk '$2=="NIXOS_SD"{print $1}')"
[[ -n "$ROOT_PART" ]] || { echo "error: no NIXOS_SD partition on $DEV — is the image flashed?" >&2; exit 1; }

SSID="$(sops --decrypt --extract '["wifi_home_name"]' "$SECRETS")"
PSK="$(sops --decrypt --extract '["wifi_home_pass"]' "$SECRETS")"

MP="$(mktemp -d)"
cleanup() { sudo umount "$MP" 2>/dev/null || true; rmdir "$MP" 2>/dev/null || true; }
trap cleanup EXIT

sudo mount "$ROOT_PART" "$MP"
sudo mkdir -p "$MP/var/lib"
printf 'WIFI_SSID=%s\nWIFI_PSK=%s\n' "$SSID" "$PSK" | sudo tee "$MP/var/lib/wifi.env" >/dev/null
sudo chmod 600 "$MP/var/lib/wifi.env"
sudo chown 0:0 "$MP/var/lib/wifi.env"
sync

echo "provisioned wifi '$SSID' onto $ROOT_PART:/var/lib/wifi.env"
