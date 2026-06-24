# Ubuntu / Debian specifics

OS-specific steps referenced from [`setup_server.md`](./setup_server.md). Plain POSIX
`sh` — runs under dash or bash.

> [!WARNING]
> **GLIBC age.** Ubuntu 22.04 ships GLIBC 2.35. Several prebuilt binaries in the
> generic instructions are built against newer glibc and **will not run** on 22.04
> (`GLIBC_2.38 not found`). See the per-tool notes below. Provisioning a 24.04+ box
> sidesteps most of this. Both inferno VPS boxes (Tokyo, Singapore) are 22.04, so
> the workarounds below are what's actually in use.

## Base packages

```sh
apt update
apt install -y build-essential pkg-config libssl-dev git-lfs apt-transport-https \
    ca-certificates curl gnupg fzf direnv tmux dash debian-keyring debian-archive-keyring
```

## Pin /bin/sh to dash

Debian/Ubuntu already default `/bin/sh` to dash, but a `dpkg-reconfigure` or upgrade
can flip it. Pin it non-interactively so the box is deterministic:

```sh
echo "dash dash/sh boolean true" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash
ls -l /bin/sh   # -> /usr/bin/dash
```

## Caddy

Caddy is **not** in the default Ubuntu repos (`apt install caddy` → "Unable to locate
package caddy"). Add the official Cloudsmith repo first:

```sh
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy
```

## Litestream

`dpkg -i <URL>` does **not** work — dpkg needs a local file. Download first:

```sh
LITESTREAM_VERSION=$(curl -s https://api.github.com/repos/benbjohnson/litestream/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
curl -L -o /tmp/litestream.deb "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-x86_64.deb"
dpkg -i /tmp/litestream.deb
rm /tmp/litestream.deb
```

## evil-helix — DOES NOT RUN on 22.04

The release binary needs GLIBC 2.38/2.39. On 22.04 (2.35) `hx` fails at startup
(`GLIBC_2.39 not found`). Broken on Tokyo too. Either provision 24.04+, or build
helix from source. Skip it on a 22.04 box.

## Custom tools (social_networks, server_upkeep) — binstall produces non-running binaries

The `cargo binstall --git` path in the generic Step 3 pulls release binaries built on
`ubuntu-latest` (24.04, GLIBC 2.39). They install but won't run on 22.04. Options:

- **Cross-build** against the box's glibc with `build_in_2204.sh` (produces GLIBC 2.34
  binaries), then scp into `~/.cargo/bin/` — see the warning box in `setup_server.md`.
- **Copy from an existing 22.04 box** that already has working binaries (e.g. Tokyo):
  ```sh
  scp inferno_vps_tokyo:~/.cargo/bin/{social_networks,server_upkeep} ~/tmp/
  scp ~/tmp/{social_networks,server_upkeep} NEW_BOX:~/.cargo/bin/
  ```
  `dust` is the same story (GLIBC-old enough to run, but easiest to copy from Tokyo).
