# Tiger Trade (overlays/tiger-trade.nix) exits right after login, no main window ever shows

Status: **open.** The launch path works: the welcome screen, license picker and login form all render. The login itself succeeds. Then the process exits with code 0.

## What works (2026-10-28, 7.4.9792.30944)

- 7.4 is **.NET 10** (`TigerTrade.runtimeconfig.json`: NETCore + WindowsDesktop + AspNetCore 10.0), not .NET Framework. The old `winetricks dotnet472` path could never have worked. That old prefix is parked at `~/.wine-tigertrade.dotnet472-old`.
- The installer is a WiX Burn bundle. Its last `MSCF` cabinet holds the MSI, which `msiextract` unpacks at build time, so no installer GUI runs.
- `mscoree` must stay builtin at run time: CoreCLR needs it to load IL-only assemblies. It is disabled only for `wineboot` (the Mono prompt).
- Wine's GL path fails on this hybrid AMD+NVIDIA laptop. Mesa inside wine opens the NVIDIA fd and finds no driver, then `wined3d_context_gl_set_gl_context` fails, the .NET render exception is swallowed, and the app hangs with no window. DXVK (Vulkan) fixes that.

## The exit

WorkLog: `LoggedIn` → `Symbol catalog ... bytes=2.7M` → socket `Disconnected` → `Backup/<date>_Exit.ttc` is written, which is the app's **normal** exit path. ErrorLog stays empty, and no child process is spawned.

Ruled out:
- DXVK. It exits the same way under plain wined3d (Xvfb, llvmpipe).
- A self-restart. `+process` shows no CreateProcess.

Leads:
- `Data/Settings2/SystemInfo.xml`: every CPU/GPU/disk/monitor field is `Error` and `MonitorsNumber=0`. That is .NET `System.Management` failing; `wine wmic` returns all of them fine. `seh` shows `RPC_S_SERVER_UNAVAILABLE`, and the ole logs show `CoMarshalInterface ... 0x80004002`. If the main window places itself on monitor 0 of 0, or a license check on HardwareID fails, the app would quit like this.
- TigerTrade.dll is obfuscated. `Application.Current.Shutdown()` sites: `uCfBmMuG1bdX8EG0Fca/zVThTguhtsjZOvhW9Ly.cs:659,711` and `do9wRnh8CPhB7GX6R7Yd/aluTssh8nmvUwatw19aJ.cs:2919` (`ilspycmd -p` output).

## Testing without touching the screen

Xvfb `:99` plus `DXVK_FILTER_DEVICE_NAME=llvmpipe`, screenshot with `magick import -display :99 -window root`, input with xdotool (XTEST works on Xvfb and is ignored by Xwayland on sway). On the real display, `swaymsg '[class="(?i)tigertrade.exe"] move to workspace 9'` in a loop, and `grim -T <foreign_toplevel_identifier>` to capture the hidden window.
