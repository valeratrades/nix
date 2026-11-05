"""Publishes to argv[1] `<speed> <backspaces> <gravity>`.
speed: how fast the horses should gallop, (key presses/s over the last second / argv[4]) ** argv[6], capped at argv[7].
Nonzero while the rate is at least argv[8], and a key is held or was released less than argv[2] ms ago, and the burst (no pause over argv[5] ms) has lasted argv[3] ms.
backspaces: count of backspace presses, each one a stumble.
gravity: how badly they stumble, the share of presses that were backspace (EMA with a half-life of argv[9] presses) over argv[10], capped at 1."""
import os, select, sys, time
from collections import deque
from evdev import InputDevice, ecodes, list_devices

out, STOP_S, START_S, NATIVE, GAP_S = sys.argv[1], int(sys.argv[2]) / 1000, int(sys.argv[3]) / 1000, float(sys.argv[4]), int(sys.argv[5]) / 1000
EXPONENT, MAX_SPEED, MIN_RATE = float(sys.argv[6]), float(sys.argv[7]), float(sys.argv[8])
DECAY, WORST_SHARE = 0.5 ** (1 / float(sys.argv[9])), float(sys.argv[10])
assert GAP_S >= STOP_S, "a burst can't end before its horses stop"
WINDOW_S = 1.0

# keyd grabs every physical keyboard, so its virtual one is the only device that still emits
kbd = next((d for d in map(InputDevice, list_devices()) if d.name == "keyd virtual keyboard"), None)
assert kbd is not None, "keyd virtual keyboard not present (yet)"


def publish(speed, backspaces, gravity):
    with open(out + ".tmp", "w") as f:
        f.write(f"{speed:.2f} {backspaces} {gravity:.2f}")
    os.replace(out + ".tmp", out)  # readers open per frame, so they only ever see a whole file


published = (0.0, 0, 0.0)
publish(*published)
down, presses = set(), deque()
burst_start, last_release = 0.0, -GAP_S
backspaces, share, weight, gravity = 0, 0.0, 0.0, 0.0  # share / weight is the EMA without bias toward its starting value
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
                backspace = e.code == ecodes.KEY_BACKSPACE
                backspaces += backspace
                share, weight = share * DECAY + (1 - DECAY) * backspace, weight * DECAY + (1 - DECAY)
                gravity = min(1.0, share / weight / WORST_SHARE)
            else:
                down.discard(e.code)
                last_release = now
    now = time.monotonic()
    while presses and presses[0] < now - WINDOW_S:
        presses.popleft()
    galloping = (down or now < last_release + STOP_S) and now - burst_start >= START_S
    rate = (len(presses) - 1) / (presses[-1] - presses[0]) if len(presses) > 1 else 0.0  # intervals, so a burst's first second isn't overcounted
    speed = round(min(MAX_SPEED, (rate / NATIVE) ** EXPONENT), 2) if galloping and rate >= MIN_RATE else 0.0
    state = (speed, backspaces, round(gravity, 2))
    if state != published:
        publish(*state)
        published = state
