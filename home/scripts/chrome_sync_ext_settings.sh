# Mirror extension storage from the Default profile into every other profile.
# Leveldb can't be touched under a live Chrome, so this only runs on cold start.
data="$HOME/.config/google-chrome"
lock="$data/SingletonLock"
if [ -L "$lock" ] && kill -0 "$(readlink "$lock" | sed 's/.*-//')" 2>/dev/null; then
  exit 0
fi

# Wallet vaults stay per-profile.
blacklist=" egjidjbpglichdcondbcbdnbeeppgdph nkbihfbeogaeaoehlefnkodbefgpgknn " # Trust Wallet, MetaMask

src="$data/Default"
mapfile -t profiles < <(jq -r '.profile.info_cache | keys[] | select(. != "Default")' "$data/Local State")

for dir in "Local Extension Settings" "Sync Extension Settings"; do
  [ -d "$src/$dir" ] || continue
  for ext in "$src/$dir"/*/; do
    id=$(basename "$ext")
    [[ $blacklist == *" $id "* ]] && continue
    for p in "${profiles[@]}"; do
      mkdir -p "$data/$p/$dir"
      rsync -a --delete "$ext" "$data/$p/$dir/$id/"
    done
  done
done

for db in "$src"/IndexedDB/chrome-extension_*; do
  [ -e "$db" ] || continue
  name=$(basename "$db")
  id=${name#chrome-extension_}
  id=${id%%_*}
  [[ $blacklist == *" $id "* ]] && continue
  for p in "${profiles[@]}"; do
    mkdir -p "$data/$p/IndexedDB"
    rsync -a --delete "$db/" "$data/$p/IndexedDB/$name/"
  done
done
