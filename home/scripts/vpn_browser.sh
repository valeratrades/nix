# Chromium through Proton VPN, inside the shared `vpn_ns` namespace.
# `vpn_browser` - throwaway incognito session; `vpn_browser <profile>` - persistent profile, logins kept.
state="${XDG_STATE_HOME:-$HOME/.local/state}/vpn_browser"
mkdir -p "$state/profiles"

profile=
proxy=
while (($#)); do
	case $1 in
	--proxy)
		(($# >= 2)) || { echo "--proxy requires host:port:user:password" >&2; exit 2; }
		proxy=$2
		shift 2
		;;
	--proxy=*)
		proxy=${1#--proxy=}
		shift
		;;
	-*)
		echo "usage: vpn_browser [profile] [--proxy host:port:user:password]" >&2
		exit 2
		;;
	*)
		[[ -z $profile ]] || { echo "usage: vpn_browser [profile] [--proxy host:port:user:password]" >&2; exit 2; }
		profile=$1
		shift
		;;
	esac
done

if [[ -n $proxy ]]; then
	IFS=: read -r proxy_host proxy_port proxy_user proxy_password proxy_extra <<< "$proxy"
	[[ -n $proxy_host && -n $proxy_port && -n $proxy_user && -n $proxy_password && -z $proxy_extra ]] || {
		echo "invalid proxy; expected host:port:user:password" >&2
		exit 2
	}
	[[ $proxy_port =~ ^[0-9]+$ ]] || { echo "invalid proxy port: $proxy_port" >&2; exit 2; }
	proxy_arg="http://${proxy_user}:${proxy_password}@${proxy_host}:${proxy_port}"
fi

if [[ -n $profile ]]; then
	data="$state/profiles/$profile"
	mode=()
else
	data=$(mktemp -d)
	trap 'rm -rf "$data"' EXIT
	mode=(--incognito)
fi

chromium_args=(
	--accept-lang=en-US,en
	--user-data-dir="$data"
	"${mode[@]}"
	--no-first-run
	--no-default-browser-check
)
[[ -n $proxy ]] && chromium_args+=(--proxy-server="$proxy_arg")

if [[ -n $proxy ]]; then
	TZ=UTC LC_ALL=en_US.UTF-8 LANGUAGE=en_US chromium "${chromium_args[@]}"
else
	TZ=UTC LC_ALL=en_US.UTF-8 LANGUAGE=en_US vpn_ns chromium "${chromium_args[@]}"
fi
