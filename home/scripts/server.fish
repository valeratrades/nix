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

function vincent_connect
    ssh_connect $VINCENT_SSH_HOST $VINCENT_SSH_PASSWORD
end

#BUG: doesn't work in sequence. The next `expect` command hops onto the previous `expect` session no matter what.
function server
    if test -z "$argv[1]" -o "$argv[1]" = "ssh"
        vincent_connect
    else if test "$argv[1]" = "connect"
        vincent_connect &
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
    ssh_connect $LINODE_SSH_HOST $LINODE_SSH_PASSWORD
end

function masha_ssh
    ssh_connect $MASHA_SSH_HOST $MASHA_SSH_PASSWORD
end
