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
ssh $MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/tmux ~/.config'
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

```sh
# detect OS and install packages
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            apt update
            apt install -y build-essential pkg-config libssl-dev git-lfs apt-transport-https ca-certificates curl gnupg fzf direnv tmux neovim
            # ClickHouse (official repo - Ubuntu's default is ancient 18.x, we need 21.8+)
            curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
            apt update
            apt install -y clickhouse-server clickhouse-client
            ;;
        fedora)
            dnf install -y gcc gcc-c++ make pkg-config openssl-devel git-lfs ca-certificates curl gnupg fzf direnv tmux neovim
            # ClickHouse (official repo)
            curl -fsSL https://packages.clickhouse.com/rpm/clickhouse.repo | tee /etc/yum.repos.d/clickhouse.repo
            dnf install -y clickhouse-server clickhouse-client
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

# disable SELinux (required for Nix on Fedora)
if command -v setenforce &> /dev/null; then
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

# install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon --yes

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
# add GitHub to known hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null

# start ssh-agent and add key (for git access)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# install social_networks
cargo install --git https://github.com/valeratrades/social_networks --branch master

# install server_upkeep
cargo install --git https://github.com/valeratrades/server_upkeep --branch master
```

---

## Step 4: Server — Running Scripts

```sh
mkdir -p ~/s
cd ~/s

# clone projects
git clone git@github.com:valeratrades/site.git
```

Start a tmux session with windows for each service:
```sh
tmux new-session -d -s main -c ~/s
tmux rename-window -t main:0 social_networks
tmux new-window -t main -n site -c ~/s/site
tmux new-window -t main -n server_upkeep -c ~/s
tmux attach -t main
```

- **Window 0**: `social_networks`
- **Window 1**: `site` (see [site README installation section](https://github.com/valeratrades/site#installation) for setup)
- **Window 2**: `server_upkeep`
