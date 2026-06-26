# rpi5 — Raspberry Pi 5

Self-contained aarch64 host built via `nixos-raspberrypi.lib.nixosSystem`
(brings its own nixpkgs + vendor kernel/firmware). Deliberately **not** wired
through the x86_64/desktop machinery in `outputs/default.nix`.

User `admin` (your SSH keys), openssh on, NetworkManager, bluetooth, vc4
display, 16k pages. Root partition auto-expands to fill the card on first boot.

## Initialising a new card (full procedure)

Building the aarch64 image on an x86_64 host needs `aarch64-linux` binfmt
emulation — already enabled in `hosts/v-laptop/configuration.nix`
(`boot.binfmt.emulatedSystems`).

```sh
# 1. Build the SD image (heavy packages come prebuilt from nixos-raspberrypi's cachix)
nix build --accept-flake-config -o /tmp/rpi5-image \
  '.#nixosConfigurations.rpi5.config.system.build.sdImage'

# 2. Flash it (find the card first: lsblk — it's the USB disk; here /dev/sda)
zstd -dc /tmp/rpi5-image/sd-image/*.img.zst \
  | sudo dd of=/dev/sda bs=4M conv=fsync iflag=fullblock status=progress

# 3. Provision the wifi secret onto the card from sops (THE step not to forget)
./hosts/rpi5/provision-wifi.sh /dev/sda
```

Then put the card in the Pi and power on. After ~1–2 min:
`ssh admin@<pi-ip>` (find the IP on your router; mDNS/`.local` isn't enabled).

## Why wifi is provisioned separately

The wifi PSK must be present before the Pi's first boot, but a fresh image has
no key to decrypt sops with — giving it one would mean shipping a decryption
key on the card. So the secret stays in sops (`secrets/users/v/default.json`:
`wifi_home_name`, `wifi_home_pass`) and `provision-wifi.sh` decrypts it on the
trusted laptop and writes it to `/var/lib/wifi.env` on the card — the only
place the cleartext PSK ever lives. The Nix config holds no wifi literals;
`networking.networkmanager.ensureProfiles` reads `$WIFI_SSID`/`$WIFI_PSK` from
that file at boot.

Different network / new secret: edit sops
(`sops secrets/users/v/default.json`) and re-run `provision-wifi.sh`. The file
survives `nixos-rebuild` over SSH; only a fresh re-flash wipes it (re-run the
script after re-flashing).
