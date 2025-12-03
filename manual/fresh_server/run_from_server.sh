# basic necessities
apt update
apt install -y build-essential pkg-config libssl-dev nix-bin git-lfs apt-transport-https ca-certificates curl gnupg fzf
snap install procs
git lfs install

# ClickHouse (official repo - Ubuntu's default is ancient 18.x, we need 21.8+)
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list
apt update
apt install -y clickhouse-server clickhouse-client
systemctl enable clickhouse-server
systemctl start clickhouse-server

# get rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo 'source "$HOME/.cargo/env"' >> ~/.bashrc
source "$HOME/.bashrc"
rustup default nightly

# direnv
apt install direnv
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source "$HOME/.bashrc"

# install my stuff
eval "$(ssh-agent -s)" # apparently starts the agent, must run this exact command before `ssh-add`
ssh-add ~/.ssh/id_ed25519
cargo install --git https://github.com/valeratrades/social_networks --branch master

# manually get into the `site`, - until stabilized, have to load the full env
