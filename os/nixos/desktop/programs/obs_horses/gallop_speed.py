"""Publishes to argv[1] how fast the horses should gallop: (key presses/s over the last second / argv[4]) ** argv[6], capped at argv[7].
Nonzero while a key is held or was released less than argv[2] ms ago, and the burst (no pause over argv[5] ms) has lasted argv[3] ms."""
import os, select, sys, time
from collections import deque
from evdev import InputDevice, ecodes, list_devices

out, STOP_S, START_S, NATIVE, GAP_S = sys.argv[1], int(sys.argv[2]) / 1000, int(sys.argv[3]) / 1000, float(sys.argv[4]), int(sys.argv[5]) / 1000
EXPONENT, MAX_SPEED = float(sys.argv[6]), float(sys.argv[7])
assert GAP_S >= STOP_S, "a burst can't end before its horses stop"
WINDOW_S = 1.0

# keyd grabs every physical keyboard, so its virtual one is the only device that still emits
kbd = next((d for d in map(InputDevice, list_devices()) if d.name == "keyd virtual keyboard"), None)
assert kbd is not None, "keyd virtual keyboard not present (yet)"


def publish(speed):
    with open(out + ".tmp", "w") as f:
        f.write(f"{speed:.2f}")
    os.replace(out + ".tmp", out)  # readers open per frame, so they only ever see a whole file


publish(0.0)
down, presses = set(), deque()
burst_start, last_release, published = 0.0, -GAP_S, 0.0
while True:
    now = time.monotonic()
    shown = bool(down) or now < last_release + STOP_S
    wakeups = [t for t in (burst_start + START_S, None if down else last_release + STOP_S) if shown and t is not None and t > now]
    if select.select([kbd], [], [], min(wakeups) - now if wakeups else None)[0]:
        for e in kbd.read():
            if e.type != ecodes.EV_KEY or e.code >= ecodes.BTN_MISC or e.value == 2:
                continue
            now = time.monotonic()
            if e.value:
                if not (down or now < last_release + GAP_S):
                    burst_start = now
                    presses.clear()
                down.add(e.code)
                presses.append(now)
            else:
                down.discard(e.code)
                last_release = now
    now = time.monotonic()
    while presses and presses[0] < now - WINDOW_S:
        presses.popleft()
    galloping = (down or now < last_release + STOP_S) and now - burst_start >= START_S
    rate = (len(presses) - 1) / (presses[-1] - presses[0]) if len(presses) > 1 else 0.0  # intervals, so a burst's first second isn't overcounted
    speed = round(min(MAX_SPEED, (rate / NATIVE) ** EXPONENT), 2) if galloping else 0.0
    if speed != published:
        publish(speed)
        published = speed
