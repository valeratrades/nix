"""Writes `1` to argv[1] while a key is held or was released within the last argv[2] milliseconds, `0` otherwise."""
import os, select, sys, time
from evdev import InputDevice, ecodes, list_devices

HOLD_S = int(sys.argv[2]) / 1000

# keyd grabs every physical keyboard, so its virtual one is the only device that still emits
kbd = next((d for d in map(InputDevice, list_devices()) if d.name == "keyd virtual keyboard"), None)
assert kbd is not None, "keyd virtual keyboard not present (yet)"

out = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT, 0o644)
os.pwrite(out, b"0", 0)  # single byte at offset 0, so readers never see a torn value
down, release_deadline, published = set(), 0.0, False
while True:
    timeout = max(0.0, release_deadline - time.monotonic()) if published and not down else None
    if select.select([kbd], [], [], timeout)[0]:
        for e in kbd.read():
            if e.type == ecodes.EV_KEY and e.code < ecodes.BTN_MISC:
                if e.value:
                    down.add(e.code)
                else:
                    down.discard(e.code)
                    release_deadline = time.monotonic() + HOLD_S
    typing = bool(down) or time.monotonic() < release_deadline
    if typing != published:
        os.pwrite(out, b"1" if typing else b"0", 0)
        published = typing
