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

# One rsync per (dir, profile): this runs between the launcher and Chrome's exec, and one process
# per extension cost ~10s at boot. Only listed entries are included, so --delete never reaches
# blacklisted or profile-only extension storage on the receiver.
mirror() { # <dir> <glob> <entry→ext-id sed>
  local dir=$1 glob=$2 to_id=$3 filters=() entry id p
  [ -d "$src/$dir" ] || return 0
  for entry in "$src/$dir"/$glob; do
    [ -e "$entry" ] || continue
    entry=$(basename "$entry")
    id=$(sed "$to_id" <<<"$entry")
    [[ $blacklist == *" $id "* ]] && continue
    filters+=("--include=/$entry/***")
  done
  [ ${#filters[@]} -gt 0 ] || return 0
  for p in "${profiles[@]}"; do
    mkdir -p "$data/$p/$dir"
    rsync -a --delete "${filters[@]}" --exclude='*' "$src/$dir/" "$data/$p/$dir/"
  done
}
mirror "Local Extension Settings" '*' ''
mirror "Sync Extension Settings" '*' ''
mirror "IndexedDB" 'chrome-extension_*' 's/^chrome-extension_//; s/_.*//'
