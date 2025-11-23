#NB: must set `MAIN_SERVER_SSH_HOST` in the env
#NB: must run this __before__ running `run_from_server.sh`

ssh-copy-id -i ~/.ssh/id_ed25519.pub $MAIN_SERVER_SSH_HOST

# setup tmux
ssh $MAIN_SERVER_SSH_HOST 'mkdir -p ~/.config/tmux'
scp ~/.config/tmux/tmux.conf $MAIN_SERVER_SSH_HOST:~/.config/tmux/

scp ~/.ssh/id_ed25519 $MAIN_SERVER_SSH_HOST:~/.ssh/
scp ~/.ssh/id_ed25519.pub $MAIN_SERVER_SSH_HOST:~/.ssh/

# setup my scripts
cat ~/.config/social_networks.toml | reasonable_envsubst - | ssh $MAIN_SERVER_SSH_HOST 'cat > ~/.config/social_networks.toml'
cat ~/.config/site/config.toml | reasonable_envsubst - | ssh $MAIN_SERVER_SSH_HOST 'cat > ~/.config/site.toml'
