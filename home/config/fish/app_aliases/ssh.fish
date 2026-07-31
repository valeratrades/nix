function code_quantm
	ssh-add ~/.ssh/id_ed25519
	code --remote ssh-remote+dev-server /home/valera/$argv[1]
end

function code_vincent
	ssh-add ~/.ssh/id_ed25519
	code --remote ssh-remote+vincent /home/nixos/$argv[1]
end

function code_prlia
	ssh-add ~/.ssh/id_ed25519
	code --remote ssh-remote+p-laptop /home/p/$argv[1]
end

# Edit remote files in our own nvim: sshfs-mounts the host's root once under ~/mnt/ssh/<host>,
# so only opens/saves cross the network, never keystrokes.
# Concurrent invocations share the mount; two nvims on the same file collide on nvim's own swapfile.
function ssh_nvim -a target
	set -l parts (string split -m1 ':' -- "$target")
	if test (count $parts) -ne 2
		echo "usage: ssh_nvim [user@]host:/abs/path" >&2
		return 1
	end
	set -l host $parts[1]
	set -l path (string replace -r '^/*' '/' -- $parts[2])
	set -l mnt "$HOME/mnt/ssh/$host"

	if not grep -qF " $mnt fuse.sshfs " /proc/mounts
		mkdir -p $mnt
		or return 1
		sshfs "$host:/" $mnt -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,cache_timeout=115,attr_timeout=115,kernel_cache
		or return 1
	end

	if not test -e "$mnt$path"
		echo "no such path on $host: $path" >&2
		return 1
	end
	e "$mnt$path"
end

function ssh_nvim_umount -a host
	fusermount -u "$HOME/mnt/ssh/$host"
end

# not sure abuot the name. Especially considering it's hardcoded. But whatever.
function dump
	scp -r "$argv[1]" dev-server:/home/valera/tmp/
end
