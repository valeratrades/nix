# Fresh Server Setup

## Prerequisites

Set the server SSH host in your environment:
```pwsh
$env:MAIN_SERVER_SSH_HOST = "user@your-server-ip"
```

---

## Step 1: Local Machine — Copy SSH Keys and Configs

```pwsh
ssh-copy-id -i ~/.ssh/id_ed25519.pub $env:MAIN_SERVER_SSH_HOST
```

```sh
# setup tmux
ssh $MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/tmux ~/.config ~/.ssh'
scp ~/.config/tmux/tmux.conf "$MAIN_SERVER_SSH_HOST:~/.config/tmux/"

# copy SSH keys (for git access on server)
scp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub "$MAIN_SERVER_SSH_HOST:~/.ssh/"

# setup pwsh profile
ssh $MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/powershell'
scp "$(dirname $0)/Microsoft.PowerShell_profile.ps1" "$MAIN_SERVER_SSH_HOST:~/.config/powershell/"

# push app configs (with env substitution, prints diffs)
fish "$(dirname $0)/sink_configs.fish"
```

---

## Step 2: Server — Install Dependencies & PowerShell

SSH into the server (initially via bash):
```pwsh
ssh $env:MAIN_SERVER_SSH_HOST
```

**First, install base packages, Caddy, PowerShell, litestream, and (Fedora only)
disable SELinux — these are OS-specific. Follow the file matching your distro:**
- **[ubuntu_specific.md](./ubuntu_specific.md)** (also covers the GLIBC 2.35 gotchas for prebuilt binaries)
- **[fedora_specific.md](./fedora_specific.md)**

The litestream service itself is created and enabled later by `sink_configs.fish`.

Then continue with the OS-agnostic steps below (run in bash):
```sh
# upgrade direnv (distro packages are too old for PowerShell support, need 2.37+)
curl -L -o /tmp/direnv https://github.com/direnv/direnv/releases/latest/download/direnv.linux-amd64 && chmod +x /tmp/direnv && mv /tmp/direnv /usr/bin/direnv

git lfs install
git config --global alias.pl '!git pull && git lfs pull'

# set PowerShell as default shell
chsh -s /usr/bin/pwsh root

# switch /tmp from tmpfs to disk (more space, auto-cleaned daily)
systemctl mask tmp.mount
echo 'q /tmp 1777 root root 1d' > /etc/tmpfiles.d/tmp.conf
# reboot required for /tmp to move to disk

# create swapfile (Rust/Nix builds can OOM a small box without this).
# SIZE IT TO THE DISK: a 16G swapfile on a 30G disk fills it to 100% once nix +
# rustup land, which breaks builds. ~4G is right for a 2-4G-RAM / 30G-disk box.
SWAP_SIZE=4G
fallocate -l $SWAP_SIZE /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon --yes

# enable nix experimental features (flakes, nix command)
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# daily nix garbage collection (removes unreferenced store paths, but preserves ~/s/site deps)
cat > /etc/systemd/system/nix-gc.service << 'EOF'
[Unit]
Description=Nix garbage collection

[Service]
Type=oneshot
# First, update GC roots for important flakes
ExecStartPre=/bin/bash -c "cd /root/s/site && /nix/var/nix/profiles/default/bin/nix build .#devShells.x86_64-linux.default --out-link /nix/var/nix/gcroots/per-user/root/site-devshell 2>/dev/null || true"
# Then garbage collect
ExecStart=/nix/var/nix/profiles/default/bin/nix-collect-garbage
EOF

cat > /etc/systemd/system/nix-gc.timer << 'EOF'
[Unit]
Description=Daily Nix garbage collection

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now nix-gc.timer

# get rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup default nightly
rustup target add wasm32-unknown-unknown

# install evil-helix (vim-like helix editor)
EVIL_HELIX_VERSION=$(curl -s https://api.github.com/repos/usagi-flow/evil-helix/releases/latest | grep -oP '"tag_name": "\K[^"]+')
curl -L "https://github.com/usagi-flow/evil-helix/releases/download/${EVIL_HELIX_VERSION}/evil-helix-amd64-linux.tar.gz" -o /tmp/evil-helix.tar.gz
mkdir -p /opt/evil-helix
tar -xzf /tmp/evil-helix.tar.gz -C /opt/evil-helix --strip-components=1
ln -sf /opt/evil-helix/hx /usr/local/bin/hx
rm /tmp/evil-helix.tar.gz
```

Now reconnect to get PowerShell:
```pwsh
exit
ssh $env:MAIN_SERVER_SSH_HOST
```

```pwsh
# reload profile (picks up cargo, direnv)
. $PROFILE
```

---

## Step 3: Server — Install Custom Tools

First set up tmux and clone projects (cargo installs are long, run them inside tmux):

```pwsh
New-Item -ItemType Directory -Force -Path ~/s
Set-Location ~/s

# clone projects
git clone git@github.com:valeratrades/site.git

# start tmux session with a window per service
tmux new-session -d -s main -c ~/s
tmux rename-window -t main:0 social_networks
tmux new-window -t main -n site -c ~/s/site
tmux new-window -t main -n server_upkeep -c ~/s
tmux attach -t main
```

Then in a separate tmux window (or window 0 before the service starts), install the tools:

```pwsh
# add GitHub to known hosts
ssh-keyscan github.com 2>$null >> ~/.ssh/known_hosts

# start ssh-agent and add key (for git access)
Start-Service ssh-agent -ErrorAction SilentlyContinue
ssh-add ~/.ssh/id_ed25519

# install cargo-binstall itself (not bundled with rustup), then pull prebuilt
# binaries (no source builds — a small box has neither the RAM nor the patience
# to compile these from scratch)
curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

# disk-usage explorer, handy for the cleanup pass at the end
yes | cargo binstall du-dust

# NB: binstall needs the crate NAME as a positional arg even with --git,
# and the repo must publish release binaries (x86_64-unknown-linux-gnu.tar.gz)
cargo binstall -y --git https://github.com/valeratrades/social_networks social_networks
cargo binstall -y --git https://github.com/valeratrades/server_upkeep server_upkeep
```

> [!WARNING]
> **GLIBC mismatch.** The release binaries (including `du-dust`) are built on
> `ubuntu-latest` (24.04, GLIBC 2.39). On an older box (e.g. Ubuntu 22.04 = GLIBC
> 2.35) they install fine but won't run (`GLIBC_2.38 not found`). See
> [ubuntu_specific.md](./ubuntu_specific.md) for the per-tool workarounds
> (cross-build via `build_in_2204.sh`, or copy already-working binaries from an
> existing 22.04 box like Tokyo). `du-dust` from Tokyo runs on 22.04 (it links
> only GLIBC ≤2.18).

---

## Step 4: Server — Running Scripts

Before starting services, restore the DBs from R2 if backups exist (litestream.yml
replicates both `social_networks` and `site`):
```sh
mkdir -p /root/.local/state/social_networks /root/.local/state/site
litestream restore -config /root/.config/litestream.yml /root/.local/state/social_networks/db.sqlite3
litestream restore -config /root/.config/litestream.yml /root/.local/state/site/db.sqlite3
# exits non-zero if no backup exists yet — that's fine on first deploy
# restart litestream afterwards so it picks up the restored files and resumes replicating
systemctl restart litestream
```

- **Window 0** (`social_networks`): run the four long-lived subcommands, one per pane:
  `social_networks dms`, `social_networks email`, `social_networks twitter`,
  `social_networks telegram-channel-watch`
- **Window 1** (`site`): see [site README installation section](https://github.com/valeratrades/site#installation) for setup.
  > [!WARNING]
  > `site`'s `Cargo.toml` has a `[patch.crates-io]` pointing `v_exchanges` and
  > `v_utils` at sibling checkouts (`../v_exchanges/v_exchanges`, `../v_utils/v_utils`).
  > `nix build` fails (`failed to load source for dependency v_exchanges`) unless those
  > repos are also cloned as siblings under `~/s`. They are **not** currently present on
  > Tokyo either, so site isn't actually running there — clone the siblings first if you
  > genuinely need site up.
- **Window 2** (`server_upkeep`): run `server_upkeep monitor`

---

## Step 5: Server — Configure Caddy (HTTPS Reverse Proxy)

Caddy auto-manages SSL certificates via Let's Encrypt.

```pwsh
# configure Caddyfile for site
@'
valeratrades.com {
    reverse_proxy localhost:61156
}

www.valeratrades.com {
    redir https://valeratrades.com{uri} permanent
}
'@ | Set-Content /etc/caddy/Caddyfile

# enable and start caddy
systemctl enable --now caddy

# verify caddy is running
systemctl status caddy
```

DNS must have A records for `valeratrades.com` and `www.valeratrades.com` pointing to the server IP.

---

## Step 6: Server — Disk Cleanup

A 30G disk fills fast: nix store (~4-5G), rustup toolchains+docs (~3G), the swapfile,
apt/snap caches. Get usage under ~50% before considering the box done.

```sh
# see what's using space
dust -d 2 -n 25 /

# nix garbage collect (removes unreferenced store paths, incl. failed-build leftovers)
nix-collect-garbage -d

# rustup docs are big and regenerable
rm -rf ~/.rustup/toolchains/*/share/doc

# drop snaps you don't use on a server (lxd is ~600M)
snap remove --purge lxd

apt-get clean   # ubuntu/debian   (dnf clean all on fedora)
```

If still tight, the swapfile is usually the biggest single file — see the sizing note
in Step 2 (4G is plenty for a 30G box).

---

> [!NOTE]
> **root's shell is PowerShell after Step 2.** Any `ssh root@box '<bash syntax>'`
> one-liner from your local machine runs under pwsh on the server and will choke on
> bash constructs (`VAR=val cmd`, `&&` chains, `[...]`). Wrap such commands in
> `ssh root@box bash -c '...'`, or pipe a script via `ssh root@box bash -s < script.sh`.
