"""Close hidden Chrome tabs whose URL matches a kill-list pattern.

Some pages (e.g. bitunix.com/markets) peg several CPU cores with live-data
render loops and are worthless in the background. CDP has no discard command,
and setWebLifecycleState('frozen') doesn't hold on pages keeping a websocket
open — so the only reliable action is to close them. The patterns here are all
stateless listing/browse views that reopen trivially, so close is safe.

Relies on the CDP port exposed by the google-chrome-cdp bind mount
(os/nixos/desktop/services/chrome-cdp.nix).
"""

import base64
import json
import os
import socket
import struct
import sys
import urllib.request

PORT = 9222

# A hidden tab whose URL contains any of these substrings gets closed.
KILL_PATTERNS = [
    "bitunix.com/markets",
]


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


def _call(s, i, method, params=None):
    _send(s, {"id": i, "method": method, "params": params or {}})
    while True:
        r = _recv(s)
        if r.get("id") == i:
            return r


def visibility(ws_url):
    s = _ws(ws_url)
    try:
        r = _call(
            s, 1, "Runtime.evaluate",
            {"expression": "document.visibilityState", "returnByValue": True},
        )
        return r.get("result", {}).get("result", {}).get("value")
    finally:
        s.close()


def _http(path):
    url = f"http://127.0.0.1:{PORT}{path}"
    return json.load(urllib.request.urlopen(url, timeout=3))


def main():
    try:
        tabs = _http("/json")
    except OSError as e:
        print(f"no CDP on :{PORT}: {e}", file=sys.stderr)
        return 0  # Chrome not running is not an error

    browser_ws = _http("/json/version")["webSocketDebuggerUrl"]

    doomed = []
    for t in tabs:
        if t.get("type") != "page":
            continue
        url = t.get("url", "")
        if not any(pat in url for pat in KILL_PATTERNS):
            continue
        ws_url = t.get("webSocketDebuggerUrl")
        if not ws_url:
            continue
        # A discarded/sleeping matching tab has no live page to query and isn't
        # burning anything; skip it (querying would just error).
        try:
            if visibility(ws_url) == "hidden":
                doomed.append(t)
        except OSError:
            continue

    if not doomed:
        return 0

    s = _ws(browser_ws)
    try:
        for i, t in enumerate(doomed, start=1):
            r = _call(s, i, "Target.closeTarget", {"targetId": t["id"]})
            ok = r.get("result", {}).get("success")
            print(f"reaped {'ok' if ok else 'FAIL'}: {t.get('url', '')[:80]}")
    finally:
        s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
