#!/usr/bin/env bash
# Slow path of ./nix-run-cached.c, which execs this on a cache miss as
#   nix-run-cached.sh <opt-level> <path-cache-entry> <content-cache-bin> <script.rs> [args...]
# or detached as `nix-run-cached.sh --sweep` once a day.

STATE_DIR="$HOME/.cargo/target"
[ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"

# Where `cargo -Zscript` puts its per-script build. It moved to $CARGO_HOME/build
# during the 1.92 nightlies, when cargo split build-dir off target-dir; what is left
# under STATE_DIR is pre-cutover, plus whatever still runs an older pinned toolchain.
BUILD_ROOTS=("$HOME/.cargo/build" "$STATE_DIR")
: "${DEFAULT_CARGO_NIGHTLY_VERSION:?unset — set in os/nixos/desktop/environment.nix and re-login}"

NIX_EXPR='let rust_flake = builtins.getFlake "github:oxalica/rust-overlay/5106a604b3d67cffe8eb51a8bd9f04e607f0d31d"; nixpkgs_flake = builtins.getFlake "github:NixOS/nixpkgs/e73de5be04e0eff4190a1432b946d469c794e7b4"; pkgs = import nixpkgs_flake { system = builtins.currentSystem; overlays = [rust_flake.overlays.default]; }; in pkgs.rust-bin.nightly."'"$DEFAULT_CARGO_NIGHTLY_VERSION"'".default.override { extensions = ["rust-src"]; }'

cargo_env() {
	env RUSTC_WRAPPER="" CARGO_PROFILE_DEV_OPT_LEVEL="$OPT_LEVEL" PATH="$1/bin:$PATH" "$1/bin/cargo" "${@:2}"
}

# Returns on compile error or on an offline miss, leaving the callers below to run
# cargo normally so the error (or the fetch-then-retry) surfaces as it always did.
# The content entry is a hard link, so a later rebuild of the same path (which
# replaces cargo's inode) cannot change what an old content hash resolves to.
build_and_exec() {
	local exe
	exe=$(cargo_env "$1" build -Zscript --offline -q --manifest-path "$SCRIPT" --message-format=json 2>/dev/null |
		grep -o '"executable":"[^"]*"' | tail -1 | cut -d'"' -f4)
	[ -n "$exe" ] || return
	mkdir -p "${CONTENT_BIN%/*}" && ln -f "$exe" "$CONTENT_BIN" || exit
	echo "$exe" >"$BIN_CACHE"
	exec "$exe" "${@:2}"
}

# <root>/<2 hex>/<hash> holding the given binary. No match — an unrecognised layout,
# or a path outside the build roots — yields nothing rather than a guess, since the
# only consumer of this deletes what it returns.
build_dir_of() {
	local root rest h1 h2
	for root in "${BUILD_ROOTS[@]}"; do
		[[ $1 == "$root"/* ]] || continue
		rest="${1#"$root"/}"
		h1="${rest%%/*}"
		rest="${rest#*/}"
		h2="${rest%%/*}"
		[[ $h1 =~ ^[0-9a-f]{2}$ && -n $h2 && $h2 != "$rest" ]] || return 1
		printf '%s/%s/%s\n' "$root" "$h1" "$h2"
		return 0
	done
	return 1
}

# A build dir is worth keeping only while something still runs the script that
# produced it. Dirs nothing points at get a longer grace period: they belong to
# scripts this wrapper never saw — `cargo -Zscript` by hand, or another wrapper.
sweep_stale_builds() {
	local unused_after grace_after
	unused_after=$(mktemp) && grace_after=$(mktemp) || return
	touch -d '30 days ago' "$unused_after"
	touch -d '90 days ago' "$grace_after"

	# Two passes: a script has one build dir but can have several cache entries
	# (one per toolchain/profile it was ever built under), so nothing may be
	# deleted until every entry has had its say.
	local live=() dropped=() cache bin dir root
	for cache in "$STATE_DIR"/.bin-*; do
		[ -f "$cache" ] || continue
		bin=$(<"$cache")
		dir=$(build_dir_of "$bin")
		if [ "$cache" -ot "$unused_after" ]; then
			rm -f "$cache"
			[ -n "$dir" ] && dropped+=("$dir")
		elif [ -n "$dir" ]; then
			live+=("$dir")
		fi
	done

	for dir in "${dropped[@]}"; do
		[[ " ${live[*]} " == *" $dir "* ]] || rm -rf "$dir"
	done

	for root in "${BUILD_ROOTS[@]}"; do
		for dir in "$root"/*/*/; do
			dir="${dir%/}"
			[ -d "$dir" ] || continue
			[[ " ${live[*]} " == *" $dir "* ]] && continue
			[ "$dir" -ot "$grace_after" ] && rm -rf "$dir"
		done
	done

	# Links nothing else shares any more: cargo dropped or replaced the build they snapshot.
	[ -d "$STATE_DIR/.content" ] && find "$STATE_DIR/.content" -type f -links 1 ! -newer "$unused_after" -delete

	rm -f "$unused_after" "$grace_after"
}

try_fix_root_owned_dirs() {
	[ "$(id -u)" = "0" ] && return 1

	# Fix any root-owned files/dirs in cargo's build tree (from accidental sudo runs)
	# Cargo's -Zscript hashes the script path, so `sudo 2fa` created
	# /home/v/.cargo/build/2b/... as root, blocking normal user builds.
	local root_owned
	root_owned=$(find "${BUILD_ROOTS[@]}" -maxdepth 2 -user root 2>/dev/null | head -1)
	[ -z "$root_owned" ] && return 1

	echo "WARN: $root_owned was root-owned, fixing" >&2
	sudo chown -R "$(id -un):$(id -gn)" "$root_owned" 2>/dev/null
}

# Get rust toolchain store path (cached to avoid 2+ second nix eval overhead).
# Keyed on the expression, so bumping the pin invalidates the cache instead of
# silently keeping the old toolchain alive.
get_rust_store_path() {
	RUST_STORE_PATH_CACHE="$STATE_DIR/.rust-store-path-$(printf '%s' "$NIX_EXPR" | md5sum | cut -c1-8)"
	if [ -f "$RUST_STORE_PATH_CACHE" ]; then
		local cached_path
		cached_path=$(<"$RUST_STORE_PATH_CACHE")
		if [ -d "$cached_path" ]; then
			echo "$cached_path"
			return 0
		fi
		# Cached path was garbage-collected, remove stale cache
		rm -f "$RUST_STORE_PATH_CACHE"
	fi

	return 1
}

if [[ $1 == --sweep ]]; then
	sweep_stale_builds
	exit
fi
OPT_LEVEL=$1 BIN_CACHE=$2 CONTENT_BIN=$3 SCRIPT=$4
shift 4

# Always run offline: cargo resolves from the local registry cache even for
# scripts it has never built, so the network is only ever needed for deps that
# were genuinely never downloaded. RUSTC_WRAPPER="" disables sccache from cargo
# config to avoid version mismatches; PATH must include the nix rust bin so
# cargo finds the correct rustc.
run_cargo() {
	cargo_env "$1" -Zscript --offline -q "$SCRIPT" "${@:2}"
}

# rc 101 is ambiguous: program panic, compile error, or offline resolution
# failure. A build-only probe (no program output mixed in, so stderr is safe to
# capture) tells them apart: probe succeeds -> the program itself exited 101;
# probe fails mentioning offline -> fetch deps online once, then run offline;
# otherwise -> compile error, already printed by the run attempt.
recover_101() {
	local err
	if err=$(cargo_env "$1" build -Zscript -q --offline --manifest-path "$SCRIPT" 2>&1); then
		exit 101
	fi
	if ! grep -q offline <<<"$err"; then
		exit 101
	fi
	notify-send "fetching crates for $(basename "$SCRIPT")..." -t 3000 2>/dev/null &
	cargo_env "$1" build -Zscript -q --manifest-path "$SCRIPT" || exit $?
	run_cargo "$1" "${@:2}"
	exit $?
}

run_script() {
	build_and_exec "$@"
	run_cargo "$1" "${@:2}"
	local rc=$?
	if [ $rc -ne 0 ] && try_fix_root_owned_dirs; then
		run_cargo "$1" "${@:2}"
		rc=$?
	fi
	[ $rc -eq 101 ] && recover_101 "$1" "${@:2}"
	exit $rc
}

# Try to use cached store path for instant startup
if RUST_PATH=$(get_rust_store_path); then
	run_script "$RUST_PATH" "$@"
fi

# Cache miss - need to fetch
notify-send "nix cache miss, fetching..." -t 3000 2>/dev/null &

# Build and cache the store path; -o registers a gc root so the toolchain
# can't be garbage-collected out from under us (which would force this
# network-requiring nix eval at some random later run).
if ! RUST_PATH=$(nix build -o "$STATE_DIR/.rust-toolchain" --print-out-paths --impure --expr "$NIX_EXPR" 2>/dev/null); then
	echo "nix build failed" >&2
	exit 1
fi
echo "$RUST_PATH" >"$RUST_STORE_PATH_CACHE"
run_script "$RUST_PATH" "$@"
