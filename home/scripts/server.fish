# TODO: rename stuff in here. And potentially replace some of these with /usr/bin/sshpass
# TODO: Move to [SSHFS](<https://en.wikipedia.org/wiki/SSHFS>)

set -l README """\
#server ssh script
do \033[34mserver\033[0m to ssh into vincent
do \033[34mserver disconnect\033[0m to close all sessions"""

function ssh_connect
	set host $argv[1]
	set password $argv[2]
	expect -c "
	spawn ssh $host
	expect -re \".*password: \"
	send \"$password\r\"
	interact
	"
end

function server
	# if openvpn connection has been established:
	# `server ssh`
	# else if running for the first time in a session:
	# `server connect`
	# hten `server disconnect` to close

	set log_name "vincent"
	if test -z "$argv[1]" -o "$argv[1]" = "ssh"
		ssh_connect $VINCENT_SSH_HOST $VINCENT_SSH_PASS
	else if test "$argv[1]" = "vpn"
		mkdir -p "$XDG_STATE_HOME/openvpn/"
		sudo openvpn --config "$VINCENT_VPN_CONF" --auth-user-pass (echo -e "$VINCENT_VPN_USER\n$VINCENT_VPN_PASS" | psub) --auth-nocache > "$XDG_STATE_HOME/openvpn/$log_name.log" 2>&1 &
	else if test "$argv[1]" = "disconnect"
		sudo killall openvpn
	else if test "$argv[1]" = "-h" -o "$argv[1]" = "--help" -o "$argv[1]" = "help"
		printf "$README\n"
	else
		printf "$README\n"
		return 1
	end
end

function linode_ssh
	ssh_connect $LINODE_SSH_HOST $LINODE_SSH_PASS
end

function masha_ssh
	ssh -i ~/.ssh/id_ed25519 m@100.107.132.25
end

function tima_ssh
	ssh -i ~/.ssh/id_ed25519 t@100.103.90.12
end
