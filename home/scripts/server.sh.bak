# TODO: rename stuff in here. And potentially replace some of these with /usr/bin/sshpass
# TODO: Move to [SSHFS](<https://en.wikipedia.org/wiki/SSHFS>)

local README="""\
#server ssh script
  do \033[34mserver\033[0m to ssh into vincent
  do \033[34mserver disconnect\033[0m to close all sessions"""


ssh_connect() {
	host="${1}"
	password="${2}"
	expect -c "
	spawn ssh ${host}
	expect -re \".*password: \"
	send \"${password}\r\"
	interact
	"
}

vincent_connect() {
	export VINCENT_SSH_PASSWORD VINCENT_SSH_HOST
	ssh_connect $VINCENT_SSH_HOST $VINCENT_SSH_PASSWORD
}

#BUG: doesn't work in sequence. The next `expect` command hops onto the previous `expect` session no matter what.
server() {
	if [ -z "$1" ] || [ "$1" = "ssh" ]; then
		vincent_connect
	elif [ "$1" = "connect" ]; then
		vincent_connect &
	elif [ "$1" = "disconnect" ]; then
		sudo killall openvpn
	elif [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
		printf "${README}\n"
	else
		printf "${README}\n"
		return 1
	fi
}

linode_ssh() {
	export LINODE_SSH_PASSWORD LINODE_SSH_HOST
	ssh_connect $LINODE_SSH_HOST $LINODE_SSH_PASSWORD
}

masha_ssh() {
	export MASHA_SSH_PASSWORD MASHA_SSH_HOST
	ssh_connect $MASHA_SSH_HOST $MASHA_SSH_PASSWORD
}
