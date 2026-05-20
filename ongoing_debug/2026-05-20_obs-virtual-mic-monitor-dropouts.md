# OBS Virtual Mic — browser audio doesn't reach virtual mic, but other apps do

## Symptom

OBS records everything correctly (mic + desktop audio = mic + browser + ffplay/beep).
But when other apps consume `obs_virtual_mic` (e.g. browser conference calls):
- `beep` (ffplay playing `~/scripts/assets/sound/Notification.mp3`) **does** appear on the virtual mic.
- Firefox / Chrome audio (YouTube etc.) **does not** appear on the virtual mic.

Both go to the same default sink. Both show movement in OBS's Audio Mixer meter for the Desktop Audio source. Both end up in the recording. Only one reaches the virtual mic.

## Architecture (current, in `home/config/pipewire/pipewire.conf.d/90-obs-virtual-mic.conf`)

```
                      ┌─── (OBS Monitor bus, libobs audio_monitoring/pulse) ─┐
default sink monitor ─┤                                                       ├─► obs-virtual-mic (null sink)
default source (mic) ─┤                                                       │            │ monitor
                      └─── (OBS Record bus, file) ──► recording               │            ▼
                                                                              │   loopback-capture
                                                                              │            │
                                                                              │            ▼
                                                                              └──► obs_virtual_mic (Audio/Source, what apps see)
```

- Null sink `obs-virtual-mic` + a loopback that exposes its monitor as `obs_virtual_mic` source (so it appears as a mic in apps).
- OBS Monitoring Device set to `OBS Virtual Mic`.
- Per OBS source: `Audio Monitoring = Monitor and Output` for Mic and Desktop Audio.

## ⚠ Critical disconfirming evidence (added 2026-05-20)

`~/nix/home/scripts/assets/sound/Notification.mp3` (what `beep` plays) is **44.1 kHz stereo MP3**. So ffplay opens a PA stream at 44.1k and gets resampled to 48k by pipewire-pulse — identical to YouTube's chain. Yet beep works and Firefox doesn't.

**This rules out "44.1 vs 48 kHz mismatch" as the differentiator.** The actual asymmetry between ffplay and Firefox is somewhere else. Plausible remaining candidates:
- Stream **lifecycle**: ffplay opens→writes ~1s→closes; Firefox keeps a long-lived corked/uncorked stream with WebRTC-style timing.
- **PA client API path**: ffplay = libpulse-simple synchronous; Firefox = async pa_stream with INTERPOLATE_TIMING + underflow callbacks (different resampler config in pipewire-pulse shim).
- **Capture-side jitter accumulation**: continuous source produces enough drift over time to break OBS monitor pa_stream; short burst doesn't accumulate.

Cheap discriminating experiments (no system changes):
```sh
# A: continuous 44.1k via ffplay (loop a flac) — if fails like Firefox: lifecycle/duration
# B: short clip in Chromium — if works like ffplay: Firefox-specific not browser-generic
# C: convert Notification.mp3 to 48k, beep with it — control for rate
```

## No OBS fork solves this (confirmed 2026-05-20)
- Upstream master: `libobs/audio-monitoring/` = `{null, osx, pulse, win32}`. No PipeWire.
- `wtay/obs-studio:pipewire-unified-dev` (Wim Taymans's branch): same four dirs, last 10 commits all camera/video, stale since Jan 2023. Not relevant.
- `dimtpap/obs-pipewire-audio-capture`: capture-side only, doesn't touch monitor.
- Conclusion: a "PipeWire monitoring backend" would have to be written from scratch.

## Root cause (most likely)

OBS has two **independent internal audio buses**:
1. **Record bus** — what ends up in the recording. Per-source resamplers, well-tested, works for everything.
2. **Monitor bus** — what gets written to the Monitoring Device. Implemented by `libobs/audio-monitoring/pulse/` and uses **libpulse only** (confirmed by `ldd libobs.so.30` — links to `libpulse.so.0`, no `libpipewire`). On a PipeWire system this means OBS → `pipewire-pulse` shim → PipeWire.

OBS 32.x on Linux has no PipeWire-native monitoring backend; the entire monitor path goes through the PA compat layer. The shim's per-stream resampler is the suspect — it handles steady 48 kHz sources (ffplay/beep) fine but drops/starves streams that arrive with different rate semantics (browser tab audio is internally 44.1 kHz, gets re-rated by Chromium/Firefox PipeWire integration, and the shim's monitor stream loses sync).

There's a documented related bug: **"Audio Monitor through PipeWire: Brickwall-lowpassed at 2kHz"** on OBS forums (Ubuntu Studio 24.04, OBS 32.0.0). Confirms the Monitor-via-PipeWire path has known quality issues, including some streams being filtered/dropped. Community workaround: avoid the monitor path entirely; route at PipeWire level instead.

## What we tried

### ✗ Attempt 1: PipeWire-side fix (bypass OBS monitor bus)
Added two extra loopbacks in `90-obs-virtual-mic.conf`:
- default sink monitor → `obs-virtual-mic`
- default source (mic) → `obs-virtual-mic`
Plan: virtual mic now mirrors what OBS records, OBS not in the path at all.
Result: user reported "no mic at all" in conference app. Likely cause: conference page's WebRTC stream had cached the previous PipeWire node ID across the pipewire restart and needed re-selecting in its UI. Also unclear whether OBS Monitoring Device was set back to Default as instructed.
Rolled back. **Disallowed from re-attempting touching system-side audio.**

### ✗ Attempt 2: switch OBS monitoring backend to PipeWire-native
Checked binary: `libobs.so.30` links only to `libpulse`, no `libpipewire`. No runtime toggle.
Then checked upstream source tree on master (today): `libobs/audio-monitoring/` contains only `null`, `osx`, `pulse`, `win32`. **There is no PipeWire monitoring backend in OBS source code at all** — not disabled, not optional, simply not written. The PipeWire work being merged upstream (PR #6207, dimtpap's plugin, the linux-pipewire integration) is exclusively on the *capture/input* side. The monitor/output path on Linux is libpulse → pipewire-pulse shim, period.
A rebuild would only help if we **wrote** the backend (or found a community fork that did — none found in search).

### ✗ Attempt 3: downgrade to OBS 31 (test for 32.x regression hypothesis)
Pinned nixpkgs OBS to `nixos-25.05` tip (commit `ac62194c3917d5f474c1a844b6fd6da2db95077d`) which has OBS 31.0.4. Implementation: added `pin-nixpkgs-obs` flake input, imported in `os/nixos/desktop/default.nix` via `inputs`, used `pkgs-obs.wrapOBS` + `pkgs-obs.obs-studio-plugins.*` instead of `pkgs.*`. Rebuild succeeded.
**Result: OBS 31.0.4 does not start on this GPU.** User rolled back to 32.1.2. The regression hypothesis (OBS issue #12750) remains untested — can't downgrade cheaply because of GPU compat. Code for the pin is now in git history; revert with `git revert` if/when needed.

### ✗ Attempt 4 (planned, not done): OBS Settings → Audio → Sample Rate flip (48k↔44.1k)
Not yet tested.

### ✗ Attempt 5 (planned, not done): remove all filters from Desktop Audio source
Not yet tested.

### Untested ideas
- Switch Desktop Audio source type from PulseAudio capture to `obs-pipewire-audio-capture` plugin (dimtpap/obs-pipewire-audio-capture) — different *capture* path, but monitor path stays libpulse so unlikely to help unless capture metadata is what the shim chokes on.
- Patch nixpkgs OBS derivation to apply community PipeWire-monitoring patches. Real work.
- Live with PA shim, but pin every involved sink/source/null-sink to identical rate (48000) and channel layout (stereo) to remove every resampling junction in the chain.
- Force browser to output at 48k (Firefox `media.cubeb.sample-rate`, Chrome `--audio-buffer-size`/launch flags) so it bypasses the rate negotiation that breaks the monitor stream.

## Constraints from user

- **Do not modify system-side audio** (no extra PipeWire loopbacks, no auto-routing into the null sink). The virtual mic must remain fed by OBS's Monitor output.
- Problem must be solved **inside OBS**.
- Recording mix is the source of truth; virtual mic must match it exactly.

## What we know about the environment

- OBS Studio 32.1.2 (`/nix/store/3mgvpsgbxymdhwl6n4x4bljysmghmaiv-obs-studio-32.1.2`), wrapped via `wrapped-obs-studio-32.1.2`.
- PipeWire 1.6.3 + WirePlumber + `pipewire-pulse` shim. `services.pipewire.pulse.enable = true`.
- OBS Settings → Audio → Sample Rate: **48 kHz**. Channels: **Stereo**.
- `obs-virtual-mic` null sink: stereo, FL/FR. Default audio rate (48 kHz).
- Default sink alternates between `bluez_output.80_99_E7_D2_1F_51.1` (WH-1000XM4 A2DP, 48 kHz) and `alsa_output.pci-0000_06_00.6.analog-surround-40` (ALC287). Both at 48 kHz.
- Default source: `alsa_input.pci-0000_06_00.6.analog-stereo` (ALC287 mic).
- `services.pipewire.jack.enable = true` as well — relevant if any audio is going through JACK shim.
- **`easyeffects`** is in the chain — its `easyeffects_sink` became default sink at some point during this session. Means `default sink → easyeffects_sink → real hardware sink`. Adds another resampler/clock-domain stage between apps and the physical output, *and* between apps and what OBS Desktop Audio captures (depending on whether OBS captures default-sink or a specific sink). Should be considered when interpreting test results — disabling easyeffects momentarily is a cheap discriminator.

## Test harness — `vmic_test`
Written 2026-05-20. Location: `home/scripts/vmic_test.fish`, exposed as fish alias `vmic_test` via `home/scripts/__main__.fish`. Reload shell to pick up.

What it does: records from `obs_virtual_mic` while playing a known sound through the default sink, computes RMS dB of what arrived, reports PASS/FAIL (threshold −60 dB). Battery of tests probes:
- **burst-44k / burst-48k**: short-lived ffplay (lifecycle ≈ 1s). Hypothesis: short streams pass.
- **loop-44k / loop-48k**: ffplay looping for 5s (continuous stream). Hypothesis: drift in monitor pa_stream accumulates.
- 48k versions are transcoded from the 44.1k Notification.mp3 to control for sample rate.

```
vmic_test                  # automated battery, ~20s
vmic_test capture 10       # capture-only window for the browser test:
                           #   play YouTube during the 10s, get verdict.
                           #   persists /tmp/vmic-capture.wav for Audacity.
```

Preflight checks (bail or warn cleanly):
- `obs_virtual_mic` source must exist in PipeWire.
- OBS process must be running (the monitor bus only exists when OBS lives).
- OBS monitor output must be linked to `obs-virtual-mic` (warns, doesn't bail).

**Quirk found while writing it:** `parecord` on this system ignores SIGINT but responds to SIGTERM. Script uses SIGTERM with a SIGKILL fallback after 200ms — `kill -INT` will hang `wait`.

Interpretation matrix for the result table:
- burst-* PASS and loop-* FAIL → **stream lifecycle / drift accumulation** is the culprit. Pinning rates won't help; need OBS code change or system-side routing.
- *-44k FAIL and *-48k PASS → **sample rate** is the culprit. Pinning the browser to 48k may help. (But the 44.1k beep already works in burst form, so unlikely.)
- loop-44k FAIL and loop-48k PASS → both rate and continuous-stream matter.
- Everything PASS → state changed since debugging started; record it.

Run next session with OBS open. Drop results into this doc.

## Diagnostic next step

OBS log while reproducing. Concretely:
1. Quit OBS.
2. Start OBS fresh.
3. Play YouTube ~5s, then `beep` ~5s.
4. Help → Log Files → View Current Log. Logs path: `~/.config/obs-studio/logs/`.
5. Look for:
   - `pulse-output.c` / `audio_monitor` init lines (negotiated rate, format).
   - `xrun` / `format mismatch` / `resample` warnings.
   - Per-source rate logging.

This tells us whether: (a) the monitor stream is opened but starved, (b) it's dropping packets because of resample failure, (c) Firefox-origin samples are being silenced somewhere upstream of the monitor bus.

## Useful one-liners

```sh
# Check OBS binary's audio backend libs:
ldd /run/current-system/sw/bin/obs 2>/dev/null | grep -iE 'pipewire|pulse'
find /nix/store -maxdepth 5 -name "libobs.so*" -path "*obs-studio-32*" \
  -exec ldd {} \; 2>/dev/null | grep -iE 'pipewire|pulse' | sort -u

# Live link map of virtual mic:
pw-link -l 2>&1 | grep -E 'obs-virtual-mic|virtual_mic'

# Inspect a node's negotiated rate/format:
pw-cli ls Node | grep -A20 obs-virtual-mic
wpctl inspect <id>

# Record straight from the virtual mic source (ground truth, bypasses app UI caches):
parecord --device=obs_virtual_mic /tmp/vmic.wav
# play YouTube, beep, etc., then Ctrl-C, then:
ffplay /tmp/vmic.wav
```

## References
- OBS forum: "Audio Monitor through PipeWire: Brickwall-lowpassed at 2kHz" — known monitor-path issue.
- `dimtpap/obs-pipewire-audio-capture` — PipeWire-native *capture* plugin (not monitoring).
- OBS Studio 32.0 release notes — added "prevent audio duplication when sources are set to Monitor and Output while monitoring device is also being captured" (different bug, but signals active work on the monitor pipeline).
