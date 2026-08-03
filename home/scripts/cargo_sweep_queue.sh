q="${XDG_CACHE_HOME:-$HOME/.cache}/cargo-sweepd/queue"
[[ -s $q ]] || exit 0

# A sweep unlinks inside the very target dir cargo writes into, so it never runs against a live
# build — waiting an hour is cheaper than racing a fingerprint tree.
if pgrep -u "$(id -u)" -x cargo >/dev/null; then
	echo "cargo is running, deferring"
	exit 0
fi

# Claimed by rename so a shell appending mid-drain lands in the next round instead of being
# truncated away along with the entries already handled. Dropping the claim on any exit path is
# safe: the arming hook re-queues within a day while the dir is still over threshold.
work="$q.working"
mv -- "$q" "$work"
trap 'rm -f -- "$work"' EXIT

while read -r d; do
	[[ -d $d ]] || continue
	echo "sweeping $d"
	(cd "$d" && cargo-sweep sweep --recursive --time 7)
done < <(sort -u -- "$work")
