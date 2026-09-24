# rpi5 image compiles the whole kernel under emulation

**Problem:** building `nixosConfigurations.rpi5.config.system.build.sdImage` on v-laptop
(x86_64, aarch64 via binfmt/qemu) spends hours compiling `linux_rpi-bcm2712`. A
cached kernel should make the image a matter of minutes.

## Cause (confirmed 2026-09-24)

`flake.nix` pins `nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main"`, locked at
`06c6e35` (2026-05-17) → kernel `6.12.87-unstable_20260509`. That store path is in
**no** substituter (checked nixos-raspberrypi / cache.nixos.org / valeratrades /
ev-invest). Upstream's cachix keeps only recent kernels: `main` 7e39508 and tags
v1.20260801.0 / v1.20260707.* → `6.18.34` are HITs. In June the same pin was fresh and
substituted, which is why the first flash never compiled a kernel.

Check before any build:
```sh
K=$(nix eval --accept-flake-config --raw '.?submodules=1#nixosConfigurations.rpi5.config.boot.kernelPackages.kernel.outPath')
nix path-info --store https://nixos-raspberrypi.cachix.org "$K" && echo cached || echo WILL COMPILE
```

## Cost when it misses

24-thread v-laptop, qemu-user emulation, load ~50: build started 01:57, kernel still in
modules at 06:45 (~18k of the kernel's build steps). Final time: TBD (fill in when the
build finishes).

## Fix / open items

- [x] Guard: `hosts/rpi5/build-image.sh` refuses when the kernel would be compiled (tested both ways).
- [ ] Pin to a release tag instead of `main`, and bump it before building an image.
  Moves the nixpkgs both hosts share (system.nix) — the fallback moves with it, which is
  the invariant; Postgres is pinned to 17.
- [ ] Push the compiled 6.12.87 kernel to valeratrades.cachix.org so this card's
  on-box rebuilds and any reflash at this pin never compile it again.
