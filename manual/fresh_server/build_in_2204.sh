#!/usr/bin/env bash
# Runs INSIDE ubuntu:22.04 container. Builds both repos against GLIBC 2.35.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== install build deps ==="
apt-get update -qq
# mold + binutils(ld) needed: both repos' .cargo/config.toml force -fuse-ld=mold
apt-get install -y -qq build-essential binutils pkg-config libssl-dev curl ca-certificates git mold >/dev/null

echo "=== install rust nightly ==="
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly >/dev/null 2>&1
source "$HOME/.cargo/env"
rustc --version

# both repos use codegen-backend=cranelift cargo-feature in Cargo.toml; that needs
# the cranelift component. Add it; if unavailable on this nightly, fall back by
# stripping the cargo-features line for the build.
rustup component add rustc-codegen-cranelift-preview 2>/dev/null || true

build_one() {
  local repo="$1"
  echo "=== building $repo (release) ==="
  cd "/work/$repo"
  # ensure we don't pick up host target/ dir artifacts from a different glibc/toolchain
  export CARGO_TARGET_DIR="/work/$repo/target-2204"
  export CARGO_BUILD_JOBS="${JOBS:-4}"
  if ! cargo build --release 2>&1 | tail -25; then
    echo "!!! build failed for $repo with cranelift; retrying with default codegen"
    # strip the cranelift codegen-backend feature line + any profile codegen-backend
    sed -i '/^cargo-features = \["codegen-backend"\]/d' Cargo.toml
    sed -i '/codegen-backend = "cranelift"/d' Cargo.toml || true
    cargo build --release 2>&1 | tail -25
  fi
  echo "=== $repo binary glibc reqs ==="
  objdump -T "target-2204/release/$repo" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -u -V | tail -3
}

build_one social_networks
build_one server_upkeep

echo "=== DONE. binaries: ==="
ls -la /work/social_networks/target-2204/release/social_networks /work/server_upkeep/target-2204/release/server_upkeep
