# Chromium through Proton VPN, inside the shared `vpn_ns` namespace.
# `vpn_browser` - throwaway incognito session; `vpn_browser <profile>` - persistent profile, logins kept.
state="${XDG_STATE_HOME:-$HOME/.local/state}/vpn_browser"
mkdir -p "$state/profiles"

case $# in
0)
	data=$(mktemp -d)
	trap 'rm -rf "$data"' EXIT
	mode=(--incognito)
	;;
1)
	data="$state/profiles/$1"
	mode=()
	;;
*)
	echo "usage: vpn_browser [profile]   existing: $(ls "$state/profiles")" >&2
	exit 1
	;;
esac

TZ=UTC LC_ALL=en_US.UTF-8 LANGUAGE=en_US vpn_ns chromium \
	--accept-lang=en-US,en \
	--user-data-dir="$data" \
	"${mode[@]}" \
	--no-first-run \
	--no-default-browser-check
