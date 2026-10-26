# Chromium through Cloudflare WARP, scoped to this process: wireproxy is a userspace WireGuard->SOCKS5 bridge, so host routes stay untouched (~/nix/tmp/ongoing_debug/2026-09-27_host-network-blackhole-warp.md).
# `vpn_browser` - throwaway incognito session; `vpn_browser <profile>` - persistent profile, logins kept.
state="${XDG_STATE_HOME:-$HOME/.local/state}/vpn_browser"
mkdir -p "$state/profiles"

if [ ! -f "$state/warp.conf" ]; then
	(cd "$state" && wgcf register --accept-tos && wgcf generate --profile warp.conf)
fi

case $# in
0)
	data=$(mktemp -d)
	throwaway="$data"
	mode=(--incognito)
	;;
1)
	data="$state/profiles/$1"
	throwaway=
	mode=()
	;;
*)
	echo "usage: vpn_browser [profile]   existing: $(ls "$state/profiles")" >&2
	exit 1
	;;
esac

port=$(shuf -i 49152-65535 -n 1)
proxy_conf=$(mktemp)
printf 'WGConfig = %s\n[Socks5]\nBindAddress = 127.0.0.1:%s\n' "$state/warp.conf" "$port" >"$proxy_conf"
wireproxy --silent --config "$proxy_conf" &
proxy=$!
trap 'kill $proxy; rm -rf "$proxy_conf" "$throwaway"' EXIT

until ss -ltnH "sport = :$port" | grep -q .; do
	kill -0 $proxy || { echo "wireproxy died" >&2; exit 1; }
	sleep 0.05
done

chromium \
	--user-data-dir="$data" \
	"${mode[@]}" \
	--proxy-server="socks5://127.0.0.1:$port" \
	--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1" \
	--force-webrtc-ip-handling-policy=disable_non_proxied_udp \
	--no-first-run \
	--no-default-browser-check
