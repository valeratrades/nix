# `pssh [ssh args]` - ssh through `vpn_ns`, offering only a key minted for that one host: the server sees a Proton IP and a key that links to nothing else.
# Own config only: ~/.ssh/config and /etc/ssh/ssh_config would add IdentityFiles, SendEnv, agent. User is a sentinel: ssh otherwise falls back to the local login name.
cfg="${XDG_RUNTIME_DIR:?}/pssh_config"
cat >"$cfg" <<'EOF'
Host *
	User pssh-no-user
	IdentitiesOnly yes
	IdentityAgent none
EOF

resolved=$(ssh -G -F "$cfg" "$@")
user=$(awk '$1 == "user" { print $2 }' <<<"$resolved")
host=$(awk '$1 == "hostname" { print $2 }' <<<"$resolved")
[ "$user" != pssh-no-user ] || { echo "pssh: give the remote user explicitly (user@host or -l)" >&2; exit 1; }

key="$HOME/.ssh/pssh/$host"
if [ ! -f "$key" ]; then
	install -d -m 700 "$HOME/.ssh/pssh"
	ssh-keygen -q -t ed25519 -N "" -C "" -f "$key" # empty comment: default is user@hostname, which ends up in authorized_keys
	echo "pssh: new key for $host, add to its authorized_keys:" >&2
	cat "$key.pub" >&2
fi

exec vpn_ns ssh -F "$cfg" -i "$key" "$@"
