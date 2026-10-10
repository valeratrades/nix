Done. APK obtained, unpacked, and run through the `apk-reverse` skill's static workflow.

## What I did
1. **Found & downloaded** The Battle Cats v15.5.0 (`jp.co.ponos.battlecatsen`). The apkcombo signed-CDN link got mangled by the fetch layer (broken AWS sig), so I used `apkeep` (built from cargo) against APKPure — clean 179 MB XAPK.
2. **Unpacked** the XAPK: base APK (28 MB code) + `InstallPack.apk` (137 MB assets) + lang/abi/dpi splits, all in `~/tmp/battle-cats/unpacked/`.
3. **Ran the reverse-skill** (`apk-reverse`, routing R1): confirmed auth precedent, then triaged with jadx (22,622 Java files), apktool (smali/manifest), and binutils on the `.so`.

## Key result
The game is a **thin JNI shell over a Cocos2d-x C++ core** — everything interesting is in `libnative-lib.so` (10.7 MB, stripped). `MyActivity` exposes `request`/`newResponse`/`onIap*` etc. Backend is a `nyanko-*.ponosgames.com` microservice fleet. Save-transfer, AES crypto (Botan), and **in-memory TLS cert pinning** are all native. `libsigner.so` is just the Adjust SDK, not a game signer.

Full report: `~/tmp/battle-cats/work/findings.md` · scope: `work/scope.md`.

**Next step** (needs your go-ahead — it's out of current scope): the real work is native analysis of `libnative-lib.so` (radare2/IDA) plus Frida hooks on the `request`/`newResponse` JNI boundary, which requires a scoped device/emulator. Want me to set that up?

Tools used: `~/tmp/battle-cats/tools/` (jadx, apktool, apkeep). No `.so` shipped for arm64 — only armeabi-v7a, so any native tooling should target ARM32.