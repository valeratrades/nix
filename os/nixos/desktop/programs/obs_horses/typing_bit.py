"""Writes `1` to argv[1] while a key was pressed within the last HOLD_S seconds, `0` otherwise."""
import os, select, sys, time
from evdev import InputDevice, ecodes, list_devices

HOLD_S = 1.5

# keyd grabs every physical keyboard, so its virtual one is the only device that still emits
kbd = next((d for d in map(InputDevice, list_devices()) if d.name == "keyd virtual keyboard"), None)
assert kbd is not None, "keyd virtual keyboard not present (yet)"

out = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT, 0o644)
os.pwrite(out, b"0", 0)  # single byte at offset 0, so readers never see a torn value
deadline = None
while True:
    timeout = None if deadline is None else max(0.0, deadline - time.monotonic())
    if select.select([kbd], [], [], timeout)[0] and any(e.type == ecodes.EV_KEY and e.value != 0 and e.code < ecodes.BTN_MISC for e in kbd.read()):
        if deadline is None:
            os.pwrite(out, b"1", 0)
        deadline = time.monotonic() + HOLD_S
    elif deadline is not None and time.monotonic() >= deadline:
        os.pwrite(out, b"0", 0)
        deadline = None
