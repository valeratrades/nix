#!/usr/bin/env python3
"""Launches nvim in a pty, then draws a gantt of its startup: --startuptime spans of the embedded server, plus lazy.nvim's
profile (plugin loads, configs, event handlers) with real timestamps, until VeryLazy + --settle, so work deferred past the first frame shows too.

usage: nvim_startup_gantt.py [--min-ms N] [--settle MS] [--runs K] [-- nvim args...]
With --runs > 1 the per-run totals are printed, then the gantt of the fastest run (the least disturbed by load).
"""
import argparse, fcntl, json, os, pty, re, select, shutil, signal, statistics, struct, sys, tempfile, termios, time

ap = argparse.ArgumentParser()
ap.add_argument('--min-ms', type=float, default=2, help='hide spans shorter than this')
ap.add_argument('--settle', type=float, default=300, help='ms to keep recording after VeryLazy')
ap.add_argument('--runs', type=int, default=1)
ap.add_argument('--timeout', type=float, default=15)
ap.add_argument('nvim_args', nargs='*')
args = ap.parse_args()

HOOK = r'''lua
local t0, ev = vim.uv.hrtime(), {}
local function at() return (vim.uv.hrtime() - t0) / 1e6 end
vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/lazy.nvim')
local U = require('lazy.core.util')
local track = U.track
U.track = function(data, time)
	if data then return track(data, time) end
	local e = track()
	local t = at()
	local d = e.data
	if type(d) == 'table' then if d.plugin then d = 'plugin ' .. d.plugin else local k, v = next(d); d = k .. ' ' .. tostring(v) end end
	ev[#ev + 1] = { kind = 'lazy', name = d, t = t, dur = e.time / 1e6 }
	return e
end
for _, e in ipairs({ 'VimEnter', 'UIEnter' }) do
	vim.api.nvim_create_autocmd(e, { once = true, callback = function() ev[#ev + 1] = { kind = 'mark', name = e, t = at() } end })
end
vim.api.nvim_create_autocmd('User', { pattern = 'VeryLazy', once = true, callback = function()
	ev[#ev + 1] = { kind = 'mark', name = 'VeryLazy', t = at() }
	vim.defer_fn(function()
		local f = assert(io.open(vim.env.NVIM_GANTT_OUT, 'w'))
		f:write(vim.json.encode(ev))
		f:close()
		vim.cmd('qa!')
	end, SETTLE)
end })
'''.replace('\n', ' ')  # --cmd takes one line; the hook's t0 is the `--cmd commands` entry of the log, so both share a clock
# Spans come from wrapping lazy's own profiler (what `:Lazy profile` shows), since LazyLoad fires on vim.schedule.
# A bare pty answers no terminal queries, and nvim blocks 100ms on the DSR one; a real terminal replies in <1ms.
REPLIES = {b'\x1b[5n': b'\x1b[0n', b'\x1b]11;?': b'\x1b]11;rgb:1e1e/1e1e/2e2e\x1b\\', b'\x1b[c': b'\x1b[?62;22c'}

ENTRY = re.compile(r'^(\d+\.\d+)\s+(\d+\.\d+)(?:\s+(\d+\.\d+))?: (.*)$')


def run(d):
	log, out = os.path.join(d, 'startuptime.log'), os.path.join(d, 'events.json')
	for p in (log, out):
		if os.path.exists(p):
			os.remove(p)
	pid, fd = pty.fork()
	if pid == 0:
		os.environ['NVIM_GANTT_OUT'] = out
		os.execvp('nvim', ['nvim', '--startuptime', log, '--cmd', HOOK.replace('SETTLE', str(int(args.settle))), *args.nvim_args])
	fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 50, 200, 0, 0))
	t0 = time.time()
	while time.time() - t0 < args.timeout:
		if select.select([fd], [], [], 0.05)[0]:
			try:
				buf = os.read(fd, 65536)  # also drained so the TUI never blocks on a full pty
			except OSError:
				break  # child exited
			for q, r in REPLIES.items():
				if q in buf:
					os.write(fd, r)
	else:
		os.killpg(pid, signal.SIGTERM)
		sys.exit(f'nvim did not reach VeryLazy + {args.settle}ms within {args.timeout}s; log: {log}')
	os.waitpid(pid, 0)
	return parse(log, out)


def parse(log, out):
	sections, cur = {}, None
	for l in open(log):
		if l.startswith('--- Startup times for process:'):
			cur = sections.setdefault(l.split(':', 1)[1].strip(' -\n'), [])
		elif cur is not None and (m := ENTRY.match(l.rstrip('\n'))):
			cur.append(m.groups())
	server = sections.get('Embedded') or sections['Primary (or UI client)']  # --headless has no UI client
	anchor = next(float(c) for c, _, _, label in server if label == '--cmd commands')
	spans = []
	for clock, a, b, label in server:
		clock, total = float(clock), float(a)
		spans.append((clock - total, clock, label))
	events = json.load(open(out))
	for e in events:
		if e['kind'] == 'lazy':
			spans.append((anchor + e['t'] - e['dur'], anchor + e['t'], f'lazy: {e["name"]}'))
	marks = {e['name']: anchor + e['t'] for e in events if e['kind'] == 'mark'}
	marks['NVIM STARTED'] = next(float(c) for c, _, _, label in server if label == '--- NVIM STARTED ---')
	return spans, marks


d = tempfile.mkdtemp(prefix='nvim_gantt_')
results = [run(d) for _ in range(args.runs)]
if args.runs > 1:
	for name in ('NVIM STARTED', 'UIEnter', 'VeryLazy'):
		v = sorted(m[name] for _, m in results if name in m)
		print(f'{name:<13} median {statistics.median(v):7.1f}ms  min {v[0]:7.1f}  max {v[-1]:7.1f}')
	print()
spans, marks = min(results, key=lambda r: r[1]['VeryLazy'])

spans = sorted((s for s in spans if s[1] - s[0] >= args.min_ms), key=lambda s: (s[0], -s[1]))
depth, ends = [], []
for a, b, _ in spans:
	ends = [e for e in ends if e > a + 1e-3]
	depth.append(sum(e >= b - 0.05 for e in ends))  # lazy spans are end - dur, so containment gets a little slack
	ends.append(b)

cols = shutil.get_terminal_size((160, 50)).columns
RUNTIME = re.compile(r'/nix/store/[^/]+/share/nvim/runtime')
labels = ['  ' * dp + RUNTIME.sub('$VIMRUNTIME', l.replace(os.path.expanduser('~'), '~')) for dp, (_, _, l) in zip(depth, spans)]
lw = min(70, max(map(len, labels), default=0))
bw = cols - lw - 11
end = max(max(b for _, b, _ in spans), *marks.values())
x = lambda ms: min(bw - 1, int(ms / end * bw))
glyph = {'NVIM STARTED': '┊', 'UIEnter': '┆', 'VeryLazy': '╎'}

step = next(s for s in (10, 20, 50, 100, 200, 500, 1000) if end / s < bw / 8)
axis = [' '] * bw
for ms in range(0, int(end) + 1, step):
	for i, c in enumerate(f'|{ms}'):
		if x(ms) + i < bw:
			axis[x(ms) + i] = c
print(' ' * (lw + 10) + ''.join(axis))
for label, (a, b, _) in zip(labels, spans):
	row = [' '] * bw
	for name, t in marks.items():
		if name in glyph:
			row[x(t)] = glyph[name]
	for i in range(x(a), max(x(a) + 1, x(b))):
		row[i] = '█'
	print(f'{label[:lw]:<{lw}} {b - a:6.1f}ms  {"".join(row)}')
print()
for name, t in sorted(marks.items(), key=lambda kv: kv[1]):
	print(f'{glyph.get(name, " ")} {name:<13} {t:7.1f}ms')
print(f'logs: {d}', file=sys.stderr)
