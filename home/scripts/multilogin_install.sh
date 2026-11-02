set -euo pipefail

state="${XDG_DATA_HOME:-$HOME/.local/share}/multilogin"
archive="$state/multilogin.zip"
install_dir="$state/app"
version="6.4.5-7"
url="https://cdn-download.multiloginapp.com/multilogin/6.4.5/multilogin-$version-linux_x86_64.zip"

mkdir -p "$state"
curl --fail --location --retry 5 --output "$archive" "$url"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$archive" -d "$tmp"
binary=$(find "$tmp" -type f -name multilogin -print -quit)
[[ -n "$binary" ]] || { echo "Multilogin archive has no multilogin executable" >&2; exit 1; }
rm -rf "$install_dir"
mkdir -p "$install_dir"
cp -a "$(dirname "$binary")"/. "$install_dir"/
chmod +x "$install_dir/multilogin"
