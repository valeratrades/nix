toolchain_path="./.cargo/rust-toolchain.toml"
if rg -q "nightly" "$toolchain_path"; then
  export RUSTFLAGS="$RUSTFLAGS -C link-arg=-fuse-ld=mold --cfg tokio_unstable -Z threads=8 -Z track-diagnostics"
fi
