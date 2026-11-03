<prompt>
what would be easiest to fully integrate with: octobrowser vs gologin vs multilogin, draw up pros and cons
</prompt>

**GoLogin is the easiest, because it's already integrated.** Octo would be the next least work, but it only gives a second copy of what Orbita already is. Multilogin is the most work, and the only one of the three that adds something new: a real Android phone.

```
                         GoLogin (Orbita)      Octo                     Multilogin cloud phone
 ─────────────────────────────────────────────────────────────────────────────────────────────
 what it is              desktop Chromium      desktop Chromium         real ARM Android in their
                         posing as Android     posing as Android        cloud, real Chrome
 in the repo today       ✅ tools/gologin,     ⛔ nothing               ⛔ desk research only
                         every verb works
 who launches the        ✅ us: the binary     ⚠ Octo's desktop app     n/a (remote phone)
   browser               from a tarball,       (local API :58888,
                         under bwrap           app running + logged in)
 camera = the film       ✅ our v4l2 node,     ⚠ ours, only if the      ⚠ desktop app's Camera
                         others hidden         app is launched inside   panel only, no API;
                                               our sandbox; Android     works on Linux? unknown
                                               profiles: no media
                                               device settings
 mic = the film's sound  ✅ PULSE_SOURCE       ⚠ same caveat            ⚠ Microphone toggle in
                         for Orbita only                                the app, unknown on Linux
 GPS / zone from point   ✅ prefs              ✅ API fingerprint        ⚠ from the proxy; no
                                                                        coordinate field, ADB
                                                                        mock location unmeasured
 proxy in the country    ✅ egress proxy CC    ✅ API                    ✅ API + built-in proxy
 automation              ✅ CDP                ✅ CDP via local API      ⚠ REST + ADB; glogin
                                                                        expires ~30–60s, scrcpy /
                                                                        adb reverse unknown
 fits emulate_android    no (its own tool)     no (a 2nd tools/ crate)  ✅ a runtime: login, geo,
                                                                        mirror, status, down
                                                                        reused
 "is this Android" to    ⚠ no                  ⚠ no                     ✅ yes
   a web page
 cost                    paid plan for API     Base plan for API        Pro 10 $11/mo, 60 min,
                                                                        then ~$0.008/min
 work left               0                     ~ a copy of              Phase 2 measuring, then
                                               tools/gologin, minus     Phases 3 and 4
                                               the parts we control
```

- **Octo** has the same weakness as Orbita: desktop Chromium with an Android user agent. On top of that, its desktop app owns the browser process, so we lose the camera isolation and per-browser mic we built for Orbita. Its Android profiles don't expose media-device settings. Octo's own Android app runs on a real phone, but there's no ADB or host-side camera path to drive it from here.
- **GoLogin** also sells cloud Android phones now, but a competitor's comparison says their API is "coming soon". I found no ADB or camera docs, so for now it can't be a device here.
- **Multilogin** is the only option that removes the "desktop posing as Android" weakness. The open question is whether its camera can be driven from Linux at all. That gets settled by Phase 2's measurements, before anything is built.

Sources:
- [Octo local client API](https://github.com/octobrowser/documentation/blob/main/api/local-client.md)
- [Octo 2.7: mobile fingerprints](https://blog.octobrowser.net/octo-browser-2-7-mobile-fingerprints)
- [Octo browser profile settings](https://docs.octobrowser.net/en/profiles/browser-profile-settings/)
- [Octo for Android](https://blog.octobrowser.net/octo-launches-an-anti-detect-browser-for-android)
- [Proxidize Octo review](https://proxidize.com/blog/octo-browser-multi-session-vs-regular-browsers/)
- [MostLogin vs GoLogin](https://www.mostlogin.com/blog/gologin-vs-mostlogin)
- [GoLogin cloud Android roundup](https://gologin.com/blog/best-cloud-android-services/)
- Multilogin: `tmp/ongoing_dev_log/2026-10-27-multilogin.md`
