#!/usr/bin/env fish
# List Chrome tabs with their renderer CPU%, hottest first.
#
# Relies on the running GUI Chrome exposing CDP on :9222 — which it does because
# its --user-data-dir is the google-chrome-cdp bind mount (a non-default path
# Chrome won't refuse the debug port for). See os/nixos/desktop/services/chrome-cdp.nix.

set -l port 9222

if not curl -s --max-time 2 http://127.0.0.1:$port/json/version >/dev/null 2>&1
    echo "No CDP on :$port — is Chrome running? (it must be launched with the configured flags)" >&2
    exit 1
end

# CDP gives title+url+a per-tab targetId; Chrome's renderer cmdline doesn't carry
# the title, so we can't perfectly join tab→pid without DevTools' SystemInfo.
# Practical join: CDP for the human-readable list, ps for the CPU picture.
echo "=== Tabs (title | url) ==="
curl -s --max-time 4 http://127.0.0.1:$port/json | python3 -c '
import sys, json
for t in json.load(sys.stdin):
    if t.get("type") == "page":
        print(f"{t.get(\"title\",\"?\")[:55]:55} | {t.get(\"url\",\"\")[:70]}")
'

echo
echo "=== Hottest renderers (cpu% rss) — match by eye to the tabs above ==="
for pid in (pgrep -f "type=renderer.*google-chrome-cdp")
    set -l cpu (ps -o %cpu= -p $pid | string trim)
    set -l rss (ps -o rss= -p $pid | string trim)
    printf "pid=%-8s cpu=%5s%%  rss=%dMB\n" $pid $cpu (math "$rss / 1024")
end | sort -t= -k3 -rn | head -12
