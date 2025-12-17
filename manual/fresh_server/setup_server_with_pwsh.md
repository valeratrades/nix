# Fresh Server Setup (PowerShell)

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

```pwsh
# setup tmux
ssh $env:MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/tmux ~/.config'
scp ~/.config/tmux/tmux.conf "${env:MAIN_SERVER_SSH_HOST}:~/.config/tmux/"

# copy SSH keys (for git access on server)
scp ~/.ssh/id_ed25519 "${env:MAIN_SERVER_SSH_HOST}:~/.ssh/"
scp ~/.ssh/id_ed25519.pub "${env:MAIN_SERVER_SSH_HOST}:~/.ssh/"

# setup pwsh profile
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
scp "$ScriptDir/.pwsh_profile.ps1" "${env:MAIN_SERVER_SSH_HOST}:~/.config/powershell/Microsoft.PowerShell_profile.ps1"

# setup app configs (with env substitution)
Get-Content ~/.config/social_networks.toml | reasonable_envsubst - | ssh $env:MAIN_SERVER_SSH_HOST 'cat > ~/.config/social_networks.toml'
Get-Content ~/.config/site.nix | reasonable_envsubst - | ssh $env:MAIN_SERVER_SSH_HOST 'cat > ~/.config/site.nix'
Get-Content ~/.config/polymarket_mm.toml | reasonable_envsubst - | ssh $env:MAIN_SERVER_SSH_HOST 'cat > ~/.config/polymarket_mm.toml'
```

---

## Step 2: Server — Install Dependencies & PowerShell

SSH into the server (initially via bash):
```pwsh
ssh $env:MAIN_SERVER_SSH_HOST
```

Install base packages and PowerShell (run in bash):
```sh
# detect OS and install packages
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            apt update
            apt install -y build-essential pkg-config libssl-dev git-lfs apt-transport-https ca-certificates curl gnupg fzf direnv tmux neovim
            # ClickHouse
            curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
            apt update
            apt install -y clickhouse-server clickhouse-client
            # PowerShell
            curl -sSL https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | tee /etc/apt/sources.list.d/microsoft-prod.list
            curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
            apt update
            apt install -y powershell
            ;;
        fedora)
            dnf install -y gcc gcc-c++ make pkg-config openssl-devel git-lfs ca-certificates curl gnupg fzf direnv tmux neovim
            # ClickHouse
            curl -fsSL https://packages.clickhouse.com/rpm/clickhouse.repo | tee /etc/yum.repos.d/clickhouse.repo
            dnf install -y clickhouse-server clickhouse-client
            # PowerShell
            curl -sSL https://packages.microsoft.com/config/rhel/9/prod.repo | tee /etc/yum.repos.d/microsoft-prod.repo
            dnf install -y powershell
            ;;
        *)
            echo "Unsupported OS: $ID"
            exit 1
            ;;
    esac
else
    echo "Cannot detect OS"
    exit 1
fi

git lfs install
git config --global alias.pl '!git pull && git lfs pull'
systemctl enable clickhouse-server
systemctl start clickhouse-server

# set PowerShell as default shell
chsh -s /usr/bin/pwsh root

# disable SELinux (required for Nix on Fedora)
if command -v setenforce &> /dev/null; then
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

# switch /tmp from tmpfs to disk (more space, auto-cleaned daily)
systemctl mask tmp.mount
echo 'q /tmp 1777 root root 1d' > /etc/tmpfiles.d/tmp.conf
# reboot required for /tmp to move to disk

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

```pwsh
# add GitHub to known hosts
ssh-keyscan github.com 2>$null >> ~/.ssh/known_hosts

# start ssh-agent and add key (for git access)
Start-Service ssh-agent -ErrorAction SilentlyContinue
ssh-add ~/.ssh/id_ed25519

# install social_networks
cargo install --git https://github.com/valeratrades/social_networks --branch master

# install server_upkeep
cargo install --git https://github.com/valeratrades/server_upkeep --branch master
```

---

## Step 4: Server — Running Scripts

```pwsh
New-Item -ItemType Directory -Force -Path ~/s
Set-Location ~/s

# clone projects
git clone git@github.com:valeratrades/site.git
```

Start a tmux session with windows for each service:
```pwsh
tmux new-session -d -s main -c ~/s
tmux rename-window -t main:0 social_networks
tmux new-window -t main -n site -c ~/s/site
tmux new-window -t main -n server_upkeep -c ~/s
tmux attach -t main
```

- **Window 0**: `social_networks`
- **Window 1**: `site` (see [site README installation section](https://github.com/valeratrades/site#installation) for setup)
- **Window 2**: `server_upkeep`
