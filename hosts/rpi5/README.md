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

Then put the card in the Pi and power on. After ~1–2 min: `ssh admin@rpi5.local`
(avahi advertises mDNS; or find the IP on your router).

## Server niceties

Built as home-manager for `admin` (`home.nix`) + a couple of host-level bits,
all reusing the laptops' own config files straight out of the flake (no copies):

- **shell**: `fish` (login shell), sourcing the shared `home/config/fish/__main__.fish`.
  `starship`/`atuin`/`zoxide`/`direnv` installed so the prompt + history match the laptops.
- **editor**: `evil-helix` (`hx`) with the shared `home/config/helix` config.
- **multiplexer**: `tmux` (no-systemd build) with the shared `home/config/tmux`.
- **CLI**: ripgrep, fd, bat, eza, dust, htop, ncdu, fzf, jq, tree, net-tools, lesspipe, git-lfs.
- **system**: daily nix GC + store auto-optimise, zram swap, `/tmp` cleared on boot.

### git is multi-user (no baked identity)

Many people share the `admin` account, so the box stores **no** git key and **no**
committer identity. Each person authenticates git with their **own** ssh key via a
forwarded agent — connect with `ssh -A admin@rpi5.local` (or `ForwardAgent yes` in
your `~/.ssh/config`). `git@github.com` then uses your forwarded key; github is
pre-trusted in `knownHosts`. `git.useConfigOnly` makes git refuse to invent a commit
author rather than mislabel one, so set `user.name`/`user.email` per-repo if you commit.
`pl` = `pull && lfs pull`, same as on desktop.

> Why no `reasonable_envsubst` here: the app deployments that needed deploy-time
> `${VAR}` substitution (site/social_networks/litestream) are intentionally not run
> on this box. The one remaining secret-bearing config — server_upkeep's telegram
> token — is injected the nixos-native way (systemd `EnvironmentFile` + config-rs
> `SERVER_UPKEEP__*` env prefix), so nothing sensitive lands in the repo or store
> and no substitution pass is needed.

### server_upkeep (disk watcher)

Runs `server_upkeep monitor` as a hardened system service (the `nixosModules.server_upkeep`
from its own flake), alerting to telegram when `/` disk usage or the state dir crosses
thresholds. Its secret lives only in `/var/lib/server_upkeep.env` (never in the repo) and
the unit stays inactive until that file exists. Provision it on the running box with:

```sh
# first add the two keys to sops: telegram_main_bot_token, telegram_alerts_channel_id
sops secrets/users/v/default.json
./hosts/rpi5/provision-server-upkeep.sh   # decrypts + scps the env file, restarts the unit
```

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
