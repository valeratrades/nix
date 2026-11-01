<prompt>
idk wtf you're talking about, phone is in, and usb debugging is on
</prompt>

The cable may be plugged in, but the laptop sees no data connection to the phone. At 15:12:33 the phone's data link on the port dropped and never came back. Since then every USB port reports nothing attached, so the phone is probably getting power only. I forced the USB bus awake to check, and it still saw nothing (I've put that setting back).

```
phone ──cable──▶ laptop port 1-2
  15:09–15:12  data link up (tethering) ✓
  15:12:33     data link dropped ──▶ since then: "not attached", no adb
```

---

Unplug the phone and plug it back in.