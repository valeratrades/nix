# Fedora specifics

OS-specific steps referenced from [`setup_server.md`](./setup_server.md). Plain POSIX
`sh` — runs under dash or bash.

> [!NOTE]
> These are the original instructions as written for Fedora. They have not been
> re-verified against a fresh Fedora box recently (the boxes currently in use are
> Ubuntu 22.04), so treat with mild suspicion — but they were correct historically.

## Base packages (+ Caddy, which IS in the Fedora repos)

```sh
dnf install -y gcc gcc-c++ make pkg-config openssl-devel git-lfs ca-certificates \
    curl gnupg fzf direnv tmux dash caddy
```

## Pin /bin/sh to dash

Fedora points `/bin/sh` at bash by default. Repoint it at dash so the POSIX snippets
run under the same interpreter as on the Ubuntu boxes:

```sh
ln -sf /usr/bin/dash /bin/sh
ls -l /bin/sh   # -> /usr/bin/dash
```

> [!NOTE]
> This only swaps the non-interactive script interpreter. root's login shell is
> unaffected (still bash via `.bashrc`). RPM scriptlets hardcode `#!/bin/sh` but are
> POSIX, so they keep working under dash.

## Litestream

`dpkg -i <URL>` does not work — download the rpm first, then install:

```sh
LITESTREAM_VERSION=$(curl -s https://api.github.com/repos/benbjohnson/litestream/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
curl -L -o /tmp/litestream.rpm "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-x86_64.rpm"
rpm -i /tmp/litestream.rpm
rm /tmp/litestream.rpm
```

## SELinux (required for Nix)

```sh
if command -v setenforce >/dev/null 2>&1; then
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi
```
