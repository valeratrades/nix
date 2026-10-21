#!/usr/bin/env python3
"""Launches an interactive `claude` in a pty, then draws a gantt of its startup from the --debug-file log.

usage: claude_startup_gantt.py [--timeout S] [--min-ms N] [-- claude args...]
Any debug line carrying `in|after|took <N>ms` becomes a span ending at that line; `Starting connection` with no
settle line is drawn as pending up to the kill. Runs `claude` from PATH directly, so not under the fish wrapper's slice.
"""
import argparse, datetime, os, pty, re, select, shutil, signal, struct, sys, tempfile, termios, fcntl, time

ap = argparse.ArgumentParser()
ap.add_argument('--timeout', type=float, default=40, help='seconds before giving up on pending MCP servers')
ap.add_argument('--min-ms', type=float, default=40, help='hide spans shorter than this')
ap.add_argument('claude_args', nargs='*')
args = ap.parse_args()

log = os.path.join(tempfile.mkdtemp(prefix='cc_gantt_'), 'debug.log')
LINE = re.compile(r'^(\S+Z) \[\w+\] (.*)$')
DUR = re.compile(r'\s*(?:\(.*?\)\s*)?\b(?:in|after|took) (\d+(?:\.\d+)?)ms\b')
MCP_START = re.compile(r'MCP server "(.+?)": Starting connection')
MCP_SETTLE = re.compile(r'MCP server "(.+?)": .*\b(?:in|after) \d+(?:\.\d+)?ms')


def ts(s):
	return datetime.datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


def parse():
	if not os.path.exists(log):
		return []
	out = []
	with open(log, errors='replace') as f:
		for l in f:
			m = LINE.match(l.rstrip('\n'))
			if m:  # continuation lines of multi-line messages carry no timestamp
				out.append((ts(m[1]), m[2]))
	return out


def pending(lines):
	started = {m[1] for _, t in lines if (m := MCP_START.search(t))}
	settled = {m[1] for _, t in lines if (m := MCP_SETTLE.search(t))}
	return started - settled


t0 = time.time()
pid, fd = pty.fork()
if pid == 0:
	os.execvp('claude', ['claude', '--debug-file', log, *args.claude_args])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 50, 200, 0, 0))

mounted_at = None
while time.time() - t0 < args.timeout:
	if select.select([fd], [], [], 0.2)[0]:
		try:
			os.read(fd, 65536)  # drained only so the TUI never blocks on a full pty
		except OSError:
			break  # child exited
	lines = parse()
	if mounted_at is None and any('REPL mounted' in t for _, t in lines):
		mounted_at = time.time()
	if mounted_at and time.time() - mounted_at > 2 and not pending(lines):  # MCP connects only begin after mount
		break
t_kill = time.time()
os.killpg(pid, signal.SIGTERM)  # pty.fork made it a session leader; this also reaps stdio MCP children
os.waitpid(pid, 0)

lines = [(t, s) for t, s in parse() if t <= t_kill]
assert lines, f'no debug output in {log}'

spans = [(0.0, lines[0][0] - t0, 'exec → first log line (binary load + JS init)', '█')]
for t, s in lines:
	if m := DUR.search(s):
		d = float(m[1]) / 1000
		if d * 1000 >= args.min_ms:
			label = (s[:m.start()] + s[m.end():]).strip(' .:')
			spans.append((t - t0 - d, t - t0, label, '█'))
for name in pending(lines):
	start = next(t for t, s in lines if (m := MCP_START.search(s)) and m[1] == name)
	spans.append((start - t0, t_kill - t0, f'MCP server "{name}": PENDING at kill', '░'))
spans.sort()
spans = [sp for i, sp in enumerate(spans) if not any(abs(sp[0] - o[0]) < 0.05 and abs(sp[1] - o[1]) < 0.05 for o in spans[:i])]  # one event often logs twice
mount = next((t - t0 for t, s in lines if 'REPL mounted' in s), None)
ready = max((b for _, b, l, _ in spans if 'session.start settled' in l), default=None)  # plugin skills, commands and panels register only after every handler calls next()

cols = shutil.get_terminal_size((160, 50)).columns
lw = min(60, max(len(l) for _, _, l, _ in spans))
bw = cols - lw - 12
end = max(e for _, e, _, _ in spans)
axis_end = max(e for a, e, _, ch in spans if e - a < 10 and ch != '░')  # a 30s connect timeout would otherwise flatten everything else
x = lambda sec: min(bw - 1, int(sec / axis_end * bw))

axis = [' '] * bw
for s in range(int(axis_end) + 1):
	axis[x(s)] = '|'
	for i, c in enumerate(f'{s}s'):
		if x(s) + 1 + i < bw:
			axis[x(s) + 1 + i] = c
print(' ' * (lw + 11) + ''.join(axis))
for a, b, label, ch in spans:
	row = [' '] * bw
	if mount is not None:
		row[x(mount)] = '┊'
	for i in range(x(a), max(x(a) + 1, x(b))):
		row[i] = ch
	if b > axis_end:
		row[-1] = '→'
	print(f'{label[:lw]:<{lw}} {b - a:6.2f}s  {"".join(row)}')
if mount is not None:
	print(f'\n┊ prompt usable (REPL mounted) at {mount:.2f}s; ' + (f'{len(pending(lines))} MCP server(s) still pending at {end:.2f}s' if pending(lines) else f'everything settled at {end:.2f}s'))
if ready is not None:
	print(f'┆ session.start chain done at {ready:.2f}s')
print(f'log: {log}', file=sys.stderr)
