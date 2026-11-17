#!/usr/bin/env python3
"""CPU cost of every defpoll in the bar: runs each command the way eww does (`sh -c` from the config dir) and reports
user+sys of the whole process tree per call, and per hour at the configured interval. Usage: poll_cost.py [runs=5]"""
import re, resource, subprocess, sys, time
from pathlib import Path

EWW = Path(__file__).resolve().parent.parent
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 5
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
UNIT_S = {"ms": 1e-3, "s": 1, "m": 60, "h": 3600}


def seconds(interval):
    m = re.fullmatch(r"([\d.]+)(ms|s|m|h)", interval)
    assert m, f"unparsed interval {interval!r}"
    return float(m[1]) * UNIT_S[m[2]]


def children_cpu():
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


rows = []
for src in sorted(EWW.glob("*.yuck")):
    for line in src.read_text().splitlines():
        m = re.match(r"\s*\(defpoll\s+(\S+)", line)
        if not m:
            continue
        interval = re.search(r':interval\s+"([^"]+)"', line)
        assert interval, f"defpoll without :interval: {line}"
        cmd = re.sub(r"\\(.)", r"\1", STRING.findall(line)[-1])  # the command is the defpoll's last string literal
        cpu = wall = 0.0
        for _ in range(RUNS):
            c0, w0 = children_cpu(), time.monotonic()
            subprocess.run(["/bin/sh", "-c", cmd], cwd=EWW, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            cpu += children_cpu() - c0
            wall += time.monotonic() - w0
        per_call = cpu / RUNS * 1e3
        rows.append((per_call * 3600 / seconds(interval[1]), per_call, wall / RUNS * 1e3, interval[1], m[1]))

rows.sort(reverse=True)
print(f"{'cpu ms/h':>10} {'cpu ms/call':>11} {'wall ms':>8} {'every':>6}  poll")
for per_hour, per_call, wall, interval, name in rows:
    print(f"{per_hour:>10.0f} {per_call:>11.1f} {wall:>8.0f} {interval:>6}  {name}")
total = sum(r[0] for r in rows)
print(f"{total:>10.0f} total = {total / 3600 / 10:.2f}% of one core")  # ms/h ÷ 3.6e6 ms/h × 100
