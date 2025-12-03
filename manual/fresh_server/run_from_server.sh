# basic necessities
apt update
apt install -y build-essential pkg-config libssl-dev nix-bin git-lfs clickhouse-client clickhouse-server
git lfs install

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
