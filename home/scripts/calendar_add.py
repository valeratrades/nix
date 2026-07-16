#!/usr/bin/env python3
"""Add an .ics event to the valeratrades@gmail.com calendar (account u/1).

Reuses the already-open Google Calendar tab via CDP (Page.navigate) so no new
tab appears; falls back to spawning a tab if no calendar tab is open. Relies on
GUI Chrome exposing --remote-debugging-port (see chrome-cdp.nix).
"""

import base64
import json
import os
import re
import socket
import struct
import subprocess
import sys
import urllib.parse
import urllib.request


def build_url(ics_path):
    raw = open(ics_path, encoding="utf-8", errors="replace").read()
    raw = raw.replace("\r\n", "\n").replace("\r", "\n")
    raw = re.sub(r"\n[ \t]", "", raw)  # RFC5545 line unfolding

    def get(name):
        m = re.search(r"^" + name + r"([^:\n]*):(.*)$", raw, re.M | re.I)
        return (m.group(1), m.group(2).strip()) if m else ("", "")

    def unesc(s):
        return s.replace("\\n", "\n").replace("\\,", ",").replace("\\;", ";")

    _, summary = get("SUMMARY")
    sp, start = get("DTSTART")
    _, end = get("DTEND")
    _, desc = get("DESCRIPTION")
    _, loc = get("LOCATION")

    s = start.strip()
    e = end.strip() or s
    q = {"text": summary or "(no title)", "dates": f"{s}/{e}"}
    if desc:
        q["details"] = unesc(desc)
    if loc:
        q["location"] = unesc(loc)
    tz = re.search(r"TZID=([^;:]+)", sp, re.I)
    if tz and not s.endswith("Z"):
        q["ctz"] = tz.group(1)
    return "https://calendar.google.com/calendar/u/1/r/eventedit?" + urllib.parse.urlencode(q)


def cdp_port():
    try:
        out = subprocess.check_output(["pgrep", "-af", "remote-debugging-port"], text=True)
    except subprocess.CalledProcessError:
        return None
    m = re.search(r"--remote-debugging-port=(\d+)", out)
    return int(m.group(1)) if m else None


def _ws(url):
    hostport, path = url[5:].split("/", 1)
    path = "/" + path
    host, port = hostport.split(":")
    s = socket.create_connection((host, int(port)), timeout=4)
    key = base64.b64encode(os.urandom(16)).decode()
    s.send(
        f"GET {path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n".encode()
    )
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(1024)
    return s


def _send(s, msg):
    p = json.dumps(msg).encode()
    mask = os.urandom(4)
    ln = len(p)
    hdr = b"\x81"
    if ln < 126:
        hdr += struct.pack("B", 0x80 | ln)
    else:
        hdr += struct.pack("B", 0x80 | 126) + struct.pack(">H", ln)
    s.send(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(p)))


def _recv(s):
    def rn(n):
        d = b""
        while len(d) < n:
            d += s.recv(n - len(d))
        return d

    while True:
        _, b1 = rn(2)
        ln = b1 & 0x7F
        if ln == 126:
            ln = struct.unpack(">H", rn(2))[0]
        elif ln == 127:
            ln = struct.unpack(">Q", rn(8))[0]
        d = rn(ln)
        try:
            return json.loads(d)
        except json.JSONDecodeError:
            continue


def _navigate(ws_url, target_url):
    s = _ws(ws_url)
    try:
        _send(s, {"id": 1, "method": "Page.navigate", "params": {"url": target_url}})
        while _recv(s).get("id") != 1:
            pass
    finally:
        s.close()


def main():
    url = build_url(sys.argv[1])
    port = cdp_port()
    if port:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=3))
        cal = next(
            (t for t in tabs if t.get("type") == "page"
             and "calendar.google.com" in t.get("url", "")
             and t.get("webSocketDebuggerUrl")),
            None,
        )
        if cal:
            _navigate(cal["webSocketDebuggerUrl"], url)
            urllib.request.urlopen(f"http://127.0.0.1:{port}/json/activate/{cal['id']}", timeout=3).read()
            print("navigated existing calendar tab")
            return
    subprocess.Popen(["google-chrome", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("opened new tab")


def _test():
    import tempfile
    ics = "BEGIN:VEVENT\r\nSUMMARY:Dentist\r\nDTSTART;TZID=Europe/Warsaw:20260720T140000\r\n" \
          "DTEND;TZID=Europe/Warsaw:20260720T150000\r\nLOCATION:Clinic\\, Rm 3\r\nEND:VEVENT\r\n"
    with tempfile.NamedTemporaryFile("w", suffix=".ics", delete=False) as f:
        f.write(ics)
        path = f.name
    u = build_url(path)
    assert "text=Dentist" in u, u
    assert "dates=20260720T140000%2F20260720T150000" in u, u
    assert "ctz=Europe%2FWarsaw" in u, u
    assert "location=Clinic%2C+Rm+3" in u, u
    # all-day passthrough
    with tempfile.NamedTemporaryFile("w", suffix=".ics", delete=False) as f:
        f.write("BEGIN:VEVENT\nSUMMARY:Holiday\nDTSTART;VALUE=DATE:20260725\nDTEND;VALUE=DATE:20260726\nEND:VEVENT\n")
        path = f.name
    u = build_url(path)
    assert "dates=20260725%2F20260726" in u, u
    assert "ctz" not in u, u
    print("ok")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        _test()
    else:
        main()
