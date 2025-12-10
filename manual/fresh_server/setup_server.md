# Fresh Server Setup

## Prerequisites

Set the server SSH host in your environment:
```sh
export MAIN_SERVER_SSH_HOST=user@your-server-ip
```

---

## Step 1: Local Machine — Copy SSH Keys and Configs

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub $MAIN_SERVER_SSH_HOST
```

```sh
# setup tmux
ssh $MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/tmux'
scp ~/.config/tmux/tmux.conf $MAIN_SERVER_SSH_HOST:~/.config/tmux/

# copy SSH keys (for git access on server)
scp ~/.ssh/id_ed25519 $MAIN_SERVER_SSH_HOST:~/.ssh/
scp ~/.ssh/id_ed25519.pub $MAIN_SERVER_SSH_HOST:~/.ssh/

# setup bashrc
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp "$SCRIPT_DIR/.bashrc" $MAIN_SERVER_SSH_HOST:~/.bashrc

# setup app configs (with env substitution)
cat ~/.config/social_networks.toml | reasonable_envsubst - | ssh $MAIN_SERVER_SSH_HOST 'cat > ~/.config/social_networks.toml'
cat ~/.config/site.nix | reasonable_envsubst - | ssh $MAIN_SERVER_SSH_HOST 'cat > ~/.config/site.nix'
cat ~/.config/polymarket_mm.toml | reasonable_envsubst - | ssh $MAIN_SERVER_SSH_HOST 'cat > ~/.config/polymarket_mm.toml'
```

---

## Step 2: Server — Install Dependencies

SSH into the server:
```sh
ssh $MAIN_SERVER_SSH_HOST
```

Then run:
```sh
# basic necessities
apt update
apt install -y build-essential pkg-config libssl-dev nix-bin git-lfs apt-transport-https ca-certificates curl gnupg fzf direnv
snap install procs
git lfs install
```

```sh
# ClickHouse (official repo - Ubuntu's default is ancient 18.x, we need 21.8+)
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
apt update
apt install -y clickhouse-server clickhouse-client
systemctl enable clickhouse-server
systemctl start clickhouse-server
```

```sh
# get rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup default nightly
```

```sh
# reload bashrc (picks up cargo, direnv)
source ~/.bashrc
```

---

## Step 3: Server — Install Custom Tools

```sh
# start ssh-agent and add key (for git access)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# install social_networks
cargo install --git https://github.com/valeratrades/social_networks --branch master
```

---

## Step 4: Server — Manual Setup

Manually clone and set up the `site` project (until stabilized, need to load the full env).
