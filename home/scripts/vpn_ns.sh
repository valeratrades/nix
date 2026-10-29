# `vpn_ns <cmd>...` - run cmd with all its traffic through Proton VPN, in a rootless netns: pasta gives the namespace egress, a WireGuard interface inside it carries everything else. Host routes stay untouched (~/nix/tmp/ongoing_debug/2026-09-27_host-network-blackhole-warp.md).
# One namespace, held by vpn_ns.service, shared by every caller: Proton sends a key's traffic to whichever endpoint spoke last, so two tunnels on one key starve each other.
wg="${XDG_STATE_HOME:-$HOME/.local/state}/vpn_browser/proton.conf" # WireGuard config from https://account.protonvpn.com/downloads
pidfile="${XDG_RUNTIME_DIR:?}/vpn_ns.pid"

case "${1:-}" in
--hold) # vpn_ns.service
	[ -f "$wg" ] || { echo "missing $wg" >&2; exit 1; }
	# own namespaces, pasta only attached: its spawn mode also unshares IPC, and X's MIT-SHM segments then don't resolve
	unshare --user --map-root-user --net --mount -- "$0" --setup &
	ns=$!
	until [ "$(readlink "/proc/$ns/ns/net")" != "$(readlink /proc/self/ns/net)" ]; do sleep 0.01; done
	pasta --config-net --quiet -4 --no-map-gw -t none -u none -T none -U none "$ns"
	wait "$ns"
	exit
	;;
--setup)
	read -r inner outer count </proc/self/uid_map
	[ "$inner $outer $count" != "0 0 4294967295" ] || { echo "refusing: would reroute the host" >&2; exit 1; }
	for _ in $(seq 100); do
		[ -n "$(ip -4 route show default)" ] && break
		sleep 0.05
	done
	read -r _ _ gw _ dev _ < <(ip -4 route show default) || { echo "pasta never configured the namespace" >&2; exit 1; }

	ip link add wg0 type wireguard
	wg setconf wg0 <(wg-quick strip "$wg")
	sed -n 's/^Address *= *//p' "$wg" | tr ',' '\n' | tr -d ' ' | grep -v : | while read -r a; do ip addr add "$a" dev wg0; done
	ip link set wg0 up
	endpoint=$(sed -n 's/^Endpoint *= *\(.*\):[0-9]*$/\1/p' "$wg")
	ip route add "$endpoint" via "$gw" dev "$dev"
	ip route del default via "$gw" dev "$dev" # no fallback: tunnel down means no network, not the host's IP
	ip route add default dev wg0

	resolv=$(mktemp)
	sed -n 's/^DNS *= *//p' "$wg" | tr ',' '\n' | tr -d ' ' | grep -v : | sed 's/^/nameserver /' >"$resolv"
	mount --bind "$resolv" /etc/resolv.conf
	nsswitch=$(mktemp)
	echo "hosts: files dns" >"$nsswitch" # mdns/mymachines would resolve outside the tunnel
	mount --bind "$nsswitch" /etc/nsswitch.conf
	mount -t tmpfs none /run/nscd # nscd resolves in the host netns
	curl -sf -m 15 https://cloudflare.com/cdn-cgi/trace >/dev/null || { echo "tunnel down, server in $wg not answering" >&2; exit 1; }

	echo $$ >"$pidfile"
	systemd-notify --ready
	exec sleep infinity
	;;
"")
	echo "usage: vpn_ns <cmd> [args]" >&2
	exit 1
	;;
esac

systemctl --user start vpn_ns.service
pid=$(<"$pidfile")
exec nsenter --target "$pid" --user --net --mount --preserve-credentials --wdns="$PWD" -- \
	unshare --user --map-user="$(id -u)" --map-group="$(id -g)" -- "$@"
