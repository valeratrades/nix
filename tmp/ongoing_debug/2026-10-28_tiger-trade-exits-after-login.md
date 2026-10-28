# Tiger Trade (overlays/tiger-trade.nix) exits right after login, no main window ever shows

Status: **blocked on the account's license.** Every Wine-side failure found so far is fixed. After a successful broker login, Tiger's own license manager reports `"License is invalid or has expired."`, and the VM-protected `AppStartup` then calls `Application.Shutdown()` without showing anything.

## Fixed (2026-10-28, 7.4.9792.30944)

- 7.4 is **.NET 10** (NETCore + WindowsDesktop + AspNetCore 10.0), not .NET Framework. The runtime comes from Microsoft's zips, and the MSI is unpacked from the Burn bundle at build time. The old dotnet472 prefix is parked at `~/.wine-tigertrade.dotnet472-old`.
- `mscoree` stays builtin at run time; CoreCLR needs it to load IL-only assemblies.
- Wine's GL path can't init on the hybrid AMD+NVIDIA laptop (Mesa inside wine opens the NVIDIA fd), so Direct3D goes through DXVK.
- `System.Management` throws `PlatformNotSupported: requires native modules from the .NET Framework`. That makes every SystemInfo field `Error`, and SystemInfo feeds the HardwareID. The fix: `HKLM\SOFTWARE\Microsoft\.NETFramework\InstallRoot` → a store dir holding `v4.0.30319\wminet_utils.dll`, plus `ucrtbase_clr0400.dll` and `vcruntime140_clr0400.dll` in system32 (Wine does not resolve imports from the DLL's own dir). All three come from `NDP48-x86-x64-AllOS-ENU.exe` → `netfx_Full.mzz`. `WmiMonitorID` (root\wmi) still fails, so `MonitorsNumber=0`.

## The exit, traced with the startup hook (`2026-10-28_tiger-trade-hook/`)

`DOTNET_STARTUP_HOOKS=C:\TtHook.dll` logs first-chance exceptions with full stacks, window open/close stacks, posted dispatcher ops, HTTP responses and JWT claims, and it dumps the license class statics/getters when the login window closes.

```
login POST auth-api.tiger.trade/api/v1/login → 200, JWT (auth0): identity + premium MARKET_SCREENER_ACCESS, no license
data-service socket LoggedIn → symbol catalog
login wizard (txmft5xtTtNdHwlIajo.kpJ74lxsuOMFA6YeCpA) success path (nFRoUy5KYVlvUS7rWc2.q9g5obgtTF case 14) → state None
  → QBvTCs8Ep9 = XdJmrYKbz2fKi4WNfnGQ.JDAKZKsC1qS()  (license active; VM method #40) = False
AppStartup (VM) → Application.CriticalShutdown via reflection
```

License state at that moment: effective license `Crypto` (`NxZbjI9pEhsOKkkBP9b.o7a9zSDxYf`), `Licenses` list null, and the license manager's own fields are all null/false with expiry `0001-01-01`. There are no exceptions between the login response and the shutdown. The `No OID value matches this name` first-chances are caught inside `CryptoConfig.MapNameToOID`. Wine's `CryptFindOIDInfo` name lookup is case-sensitive, unlike Windows, but `VerifyHash` with OIDs still works (tested).

Not confirmed: whether a Windows run of this account also gets no license. Early runs sent HardwareIDs built from `Error` fields, so if Tiger limits devices per license, those may count.

## Testing without touching the screen

Xvfb `:99` (run it as a tracked background job; a `&`-subshell dies with the tool call) plus `DXVK_FILTER_DEVICE_NAME=llvmpipe`. Screenshots with `magick import -display :99 -window root`; input with xdotool (works on Xvfb, ignored by Xwayland on sway). On the real display, `swaymsg '[class="(?i)tigertrade.exe"] move to workspace 9'` in a loop, and `grim -T <foreign_toplevel_identifier>` to capture the hidden window. Never `pkill -f 'TigerTrade.exe'`: it matches the calling shell; use `wineserver -k`.
