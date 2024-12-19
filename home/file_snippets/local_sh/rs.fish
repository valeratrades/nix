# File is source on `cs` into the project's root. Allows to define a set of project-specific commands and aliases.

# effectively a quite "cargo run" alias. Needed when I look at the errors via `cargo watch` in another window, and don't want to trash terminal history when running the code.
alias qr="./target/debug/PROJECT_NAME_PLACEHOLDER"

# very ugly wrapper for RUSTFLAGS
set toolchain_path "../.cargo/rust-toolchain.toml"
if rg -q "nightly" ./.cargo/rust-toolchain.toml
    set -x RUSTFLAGS "$RUSTFLAGS -C link-arg=-fuse-ld=mold --cfg tokio_unstable -Z threads=8 -Z track-diagnostics"
end
# stable flags are subset of nightly flags, so those are defined normally in the `cargo.toml` file
