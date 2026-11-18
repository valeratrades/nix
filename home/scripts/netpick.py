"""Uplink ladder ethernet > USB tether > best known Wi-Fi, on top of NM's connectivity penalty. valeratrades/nix#29"""
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

DRY = os.environ["NETPICK_DRY_RUN"] == "1"
WIFI, ETH, TETHER_PREFIX = "wlp4s0", "enp5s0", "enp6s0f3u"  # u<usb1 port>: the phone shows up on either USB-C port
PHONE_SSIDS = {"Valera", "Redmi Note 14"}  # the tethering phone's own hotspot, which drops once its USB tether starts
PROBE = "http://1.1.1.1/"  # by IP: DNS goes through tailscale on every link, so it says nothing about this one
TICK = 60
DEAD_TICKS = 3
GRACE = 5  # s the default-route device may go without internet before the next route takes over
FAST = 1
COOLDOWN = 300
STATE = Path(os.environ["STATE_DIRECTORY"])
HIST = STATE / "wifi.json"
RADIO_FLAG = STATE / "radio-off-by-netpick"


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True, timeout=60).stdout


def act(*a):
    print(("would run: " if DRY else "run: ") + " ".join(a), flush=True)
    if not DRY:
        sh(*a)


def fields(line):
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in re.split(r"(?<!\\):", line)]


assert fields(r"a\:b:c\\") == ["a:b", "c\\"]


def rows(*a):
    return [fields(line) for line in sh("nmcli", "-t", *a).splitlines() if line]


def probe(iface, timeout=5):
    """TCP connect time in ms over iface, None when it does not get through."""
    r = subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", str(timeout), "--interface", iface, "-w", "%{time_connect}", PROBE], capture_output=True, text=True)
    return float(r.stdout) * 1000 if r.returncode == 0 else None


def carrier():
    """Device whose default route wins now."""
    best = None
    for line in sh("ip", "-4", "route", "show", "default").splitlines():
        w = line.split()
        dev, metric = w[w.index("dev") + 1], int(w[w.index("metric") + 1]) if "metric" in w else 0
        if (dev in (ETH, WIFI) or dev.startswith(TETHER_PREFIX)) and (best is None or metric < best[1]):
            best = (dev, metric)
    return None if best is None else best[0]


def ewma(old, new):
    return new if old is None else 0.8 * old + 0.2 * new


def score(signal, h):
    # shortcut: hand-picked weights, tune once wifi.json has history from a few places
    signal = min(signal, 70)  # past usable, more bars do not make a link better
    if h is None:
        return signal + 20
    lat = 0 if h["lat_ms"] is None else min(h["lat_ms"], 500) / 5
    return signal + 40 * h["up"] - lat + min(h["rate"], 1000) / 50


class Netpick:
    def __init__(self):
        self.hist = json.loads(HIST.read_text()) if HIST.exists() else {}
        self.profiles = {}  # uuid -> ssid
        self.prio = {}  # uuid -> priority this process set
        self.blocked = set()  # phone-hotspot uuids this process took off autoconnect
        self.dead = {WIFI: 0, "tether": 0}
        self.cooldown = {}  # key -> time of the last action
        self.failing = {}  # dev -> when its probes started failing
        self.good = {}  # dev -> when its probes started passing
        self.demoted = set()  # devices this process pushed below every other route

    def failover(self):
        """NM's own check runs every 60s and needs ~20s to time out; this catches a dead carrier within GRACE."""
        c = carrier()
        for d in self.demoted | ({c} - {None}):
            start = time.monotonic()
            if probe(d, 2) is None:
                self.failing.setdefault(d, start)
                self.good.pop(d, None)
            else:
                self.good.setdefault(d, start)
                self.failing.pop(d, None)
        now = time.monotonic()
        if c is not None and c not in self.demoted and now - self.failing.get(c, now) >= GRACE:
            print(f"{c} without internet for {now - self.failing[c]:.1f}s, demoting it", flush=True)
            act("nmcli", "device", "modify", c, "ipv4.route-metric", "30000", "ipv6.route-metric", "30000")
            self.demoted.add(c)
            if RADIO_FLAG.exists():  # ethernet was the reason Wi-Fi went quiet
                act("nmcli", "radio", "wifi", "on")
                RADIO_FLAG.unlink()
        for d in [d for d in self.demoted if now - self.good.get(d, now) >= 10]:
            print(f"{d} back for 10s, restoring its route", flush=True)
            self.restore(d)

    def restore(self, d):
        self.demoted.discard(d)
        act("nmcli", "device", "reapply", d)

    def wifi_profiles(self):
        uuids = {u for u, t in rows("-f", "UUID,TYPE", "c") if t == "802-11-wireless"}
        if uuids != set(self.profiles):
            self.profiles = {u: sh("nmcli", "-g", "802-11-wireless.ssid", "c", "show", u).strip() for u in uuids}
        return self.profiles

    def cooled(self, key):
        return time.time() - self.cooldown.get(key, 0) > COOLDOWN

    def tick(self):
        devs = {d: (st, c) for d, st, c in rows("-f", "DEVICE,STATE,CONNECTION", "dev")}
        tether = next((d for d in devs if d.startswith(TETHER_PREFIX)), None)
        up = {d for d in (ETH, tether, WIFI) if devs.get(d, ("",))[0] == "connected"}
        conn = {d: sh("nmcli", "-g", "GENERAL.IP4-CONNECTIVITY", "dev", "show", d).split()[1].strip("()") for d in up}  # "4 (full)"
        lat = {d: probe(d) for d in up}
        ok = {d for d in up if lat[d] is not None or conn[d] == "full"}  # both must fail: either one alone is blocked on some networks
        # a portal is waiting on a login, not dead; an offered tether without a lease is dead
        self.dead[WIFI] = self.dead[WIFI] + 1 if WIFI in up and WIFI not in ok and conn[WIFI] != "portal" else 0
        self.dead["tether"] = self.dead["tether"] + 1 if tether is not None and tether not in ok and conn.get(tether) != "portal" else 0

        # ethernet healthy: no Wi-Fi scanning at all, unless Wi-Fi is already associated (then supplicant only bgscans on weak signal)
        radio = sh("nmcli", "radio", "wifi").strip() == "enabled"
        if ETH in ok and radio and WIFI not in up and not RADIO_FLAG.exists():
            act("nmcli", "radio", "wifi", "off")
            RADIO_FLAG.touch()
        elif ETH not in ok and RADIO_FLAG.exists():
            act("nmcli", "radio", "wifi", "on")
            RADIO_FLAG.unlink()

        aps = rows("-f", "IN-USE,SSID,SIGNAL,RATE", "dev", "wifi", "list", "--rescan", "no") if radio else []
        visible = {}
        for in_use, ssid, sig, rate in aps:
            if ssid:
                visible[ssid] = max(visible.get(ssid, 0), int(sig))
            if in_use == "*" and WIFI in up:
                h = self.hist.setdefault(ssid, {"lat_ms": None, "rate": None, "up": 1.0})
                h["up"] = ewma(h["up"], 1.0 if WIFI in ok else 0.0)
                if lat[WIFI] is not None:
                    h["lat_ms"] = ewma(h["lat_ms"], lat[WIFI])
                h["rate"] = ewma(h["rate"], float(rate.split()[0]))
                HIST.write_text(json.dumps(self.hist, indent=1))

        tethering = tether is not None
        profiles = self.wifi_profiles()
        for u, ssid in profiles.items():
            if ssid not in PHONE_SSIDS:
                continue
            if tethering and u not in self.blocked and sh("nmcli", "-g", "connection.autoconnect", "c", "show", u).strip() == "yes":
                act("nmcli", "c", "modify", "--temporary", u, "connection.autoconnect", "no")
                self.blocked.add(u)
            elif not tethering and u in self.blocked:
                act("nmcli", "c", "modify", "--temporary", u, "connection.autoconnect", "yes")
                self.blocked.remove(u)

        ranked = sorted((ssid for ssid in visible if ssid in profiles.values()), key=lambda s: -score(visible[s], self.hist.get(s)))
        for rank, ssid in enumerate(ranked):
            for u in (u for u, s in profiles.items() if s == ssid and self.prio.get(u) != 100 - rank):
                act("nmcli", "c", "modify", "--temporary", u, "connection.autoconnect-priority", str(100 - rank))
                self.prio[u] = 100 - rank

        if self.dead["tether"] >= DEAD_TICKS and self.cooled("revive"):
            print(f"tether dead for {self.dead["tether"]} ticks, cycling the phone's USB function", flush=True)
            self.cooldown["revive"] = time.time()
            act("adb", "shell", "svc", "usb", "setFunctions")
            act("timeout", "30", "adb", "wait-for-device")
            act("adb", "shell", "svc", "usb", "setFunctions", "rndis")

        if self.dead[WIFI] >= DEAD_TICKS and not ok & {ETH, tether}:
            current = devs[WIFI][1]
            options = [s for s in ranked if s != current and not (tethering and s in PHONE_SSIDS) and self.cooled(s)]
            if options:
                print(f"{current} dead for {self.dead[WIFI]} ticks, nothing healthier above it", flush=True)
                self.cooldown[current] = time.time()
                best = max((u for u, s in profiles.items() if s == options[0]), key=lambda u: self.prio.get(u, 0))
                act("nmcli", "c", "up", best)
                self.dead[WIFI] = 0


def main():
    print(f"netpick start, dry_run={DRY}", flush=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    n = Netpick()
    last_tick = 0.0
    try:
        while True:
            try:
                n.failover()
                if time.monotonic() - last_tick >= TICK:
                    last_tick = time.monotonic()
                    n.tick()
            except subprocess.CalledProcessError as e:  # one failed nmcli/adb call must not end the loop that keeps the uplink alive
                print(f"{e.cmd} exited {e.returncode}: {e.stderr.strip()}", file=sys.stderr, flush=True)
            time.sleep(FAST)
    finally:
        for d in list(n.demoted):  # a demotion must not outlive the process watching for the link's return
            n.restore(d)


main()
