# Kill headless chromium only when provably undriven: launcher dead (reparented to the user manager),
# and its DevTools port had no clients on two consecutive runs. Anything unverifiable is left alone.
set -euo pipefail

[[ $(</proc/$PPID/comm) == systemd ]] || { echo "must run as a user unit, parent is $(</proc/$PPID/comm)" >&2; exit 1; }
state="$XDG_RUNTIME_DIR/headless-chromium-reaper"
touch "$state"

idle=()
for p in $(pgrep -P "$PPID" -f 'chromium.*--headless' || true); do
	grep -qs 'app-org.chromium.Chromium-' "/proc/$p/cgroup" || continue
	key="$p:$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null)" || continue # starttime guards against pid reuse
	ports=$(ss -Htlnp | grep "pid=$p," | awk '{sub(/.*:/, "", $4); print $4}' || true)
	if [[ -z $ports ]]; then
		echo "skip $p: no DevTools port (pipe mode?), can't verify it's undriven"
		continue
	fi
	clients=0
	for port in $ports; do
		clients=$((clients + $(ss -Htn state established "( sport = :$port )" | wc -l)))
	done
	if ((clients > 0)); then
		echo "skip $p: $clients DevTools client(s)"
	elif grep -qxF "$key" "$state"; then
		echo "reaping $p"
		kill "$p"
	else
		idle+=("$key")
	fi
done
printf '%s\n' ${idle[@]+"${idle[@]}"} >"$state"
