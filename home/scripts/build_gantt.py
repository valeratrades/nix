#!/usr/bin/env python3
"""Live gantt of a cargo or nix build: one bar per crate (and per nix derivation), redrawn as the build goes.

usage: build_gantt.py cargo build [args...]  (not a cargo-limit alias like `b`: lbuild eats the json)
       build_gantt.py nix build .#pkg [args...]
Crate starts come from cargo's `Compiling` lines, ends from its `compiler-artifact` json messages; cargo gets
`--message-format=json` appended. Inside nix the derivation's own cargo has to be passed that flag
(`cargoBuildFlags`), else crates there only show as started (░ until their derivation ends).
"""
import json, os, re, shutil, subprocess, sys, threading, time

cmd = sys.argv[1:]
assert cmd and cmd[0] in ('cargo', 'nix'), __doc__
is_nix = cmd[0] == 'nix'
cmd += ['--log-format', 'internal-json', '-v'] if is_nix else ['--message-format=json']

t0 = time.monotonic()
rows = {}  # key -> [label, start, end | None, done, is_drv]
# shortcut: one bar per package (cargo prints `Compiling` once), so build-script → lib waits count as running; per-unit needs `-v`'s `Running rustc --crate-name` lines
drv_of_activity = {}
lock = threading.Lock()
log = open(f'/tmp/build_gantt_{os.getpid()}.log', 'w', buffering=1)
COMPILING = re.compile(r'^\s*(?:Compiling|Checking|Documenting) (\S+) v(\S+)')


def pkg_key(package_id):
	src, frag = package_id.rsplit('#', 1)
	if '@' in frag:
		name, ver = frag.split('@', 1)
	else:  # cargo omits the name when it equals the source's last path segment
		name, ver = src.split('?')[0].rstrip('/').rsplit('/', 1)[1], frag
	return name, ver


def on_line(line, now):
	line = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', line)
	if line.startswith('{'):
		msg = json.loads(line)
		if msg.get('reason') == 'compiler-message':
			log.write(msg['message']['rendered'])
		elif msg.get('reason') == 'compiler-artifact':
			row = rows.get(pkg_key(msg['package_id']))
			if row is not None:  # absent: fresh, never compiled this run
				row[2] = now
				row[3] |= 'custom-build' not in msg['target']['kind']
		return
	m = COMPILING.match(line)
	if m:
		rows.setdefault(m.groups(), [f'{m[1]} v{m[2]}', now, None, False, False])


def on_nix(ev, now):
	a = ev['action']
	if a == 'start' and ev.get('type') == 105:  # actBuild
		name = ev['fields'][0].split('/')[-1].split('-', 1)[1].removesuffix('.drv')
		drv_of_activity[ev['id']] = name
		rows[('drv', ev['id'])] = [f'[{name}]', now, None, False, True]
	elif a == 'stop' and ('drv', ev['id']) in rows:
		row = rows[('drv', ev['id'])]
		row[2], row[3] = now, True
	elif a == 'result' and ev.get('type') == 104 and ('drv', ev['id']) in rows:  # resSetPhase
		rows[('drv', ev['id'])][0] = f'[{drv_of_activity[ev["id"]]}] {ev["fields"][0]}'
	elif a == 'result' and ev.get('type') == 101:  # resBuildLogLine
		log.write(ev['fields'][0] + '\n')
		on_line(ev['fields'][0], now)
	elif a == 'msg' and ev['level'] == 0:
		log.write(ev['msg'] + '\n')


def reader(stream, nix_events):
	for raw in stream:
		now = time.monotonic() - t0
		line = raw.decode(errors='replace').rstrip('\n')
		with lock:
			if nix_events and line.startswith('@nix '):
				on_nix(json.loads(line[5:]), now)
			else:
				log.write(line + '\n')
				on_line(line, now)


def render(now, limit):
	cols, _ = shutil.get_terminal_size((160, 50))
	spans = sorted(rows.values(), key=lambda r: r[1])
	if limit is not None:
		running = [r for r in spans if not r[3]]
		finished = [r for r in spans if r[3]][-max(0, limit - len(running)):] if limit > len(running) else []
		spans = sorted(running[-limit:] + finished, key=lambda r: r[1])
	done = sum(r[3] for r in rows.values() if not r[4])
	crates = sum(not r[4] for r in rows.values())
	out = [f'{now:6.1f}s  {done}/{crates} crates done, {crates - done} running']
	if not spans:
		return '\n'.join(out)
	lw = min(45, max(len(r[0]) for r in spans))
	bw = max(10, cols - lw - 10)
	x = lambda sec: min(bw - 1, int(sec / max(now, 1e-9) * bw))
	axis = [' '] * bw
	step = max(1, int(now / (bw / 8)) or 1)
	for s in range(0, int(now) + 1, step):
		axis[x(s)] = '|'
		for i, c in enumerate(f'{s}s'):
			if x(s) + 1 + i < bw:
				axis[x(s) + 1 + i] = c
	out.append(' ' * (lw + 9) + ''.join(axis))
	for label, a, b, fin, _ in spans:
		end = b if fin else now
		ch = '█' if fin else ('▒' if b is not None else '░')
		row = [' '] * bw
		for i in range(x(a), max(x(a) + 1, x(end))):
			row[i] = ch
		out.append(f'{label[:lw]:<{lw}} {end - a:6.1f}s  {"".join(row)}')
	return '\n'.join(out)


proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
threads = [threading.Thread(target=reader, args=(proc.stdout, False)), threading.Thread(target=reader, args=(proc.stderr, is_nix))]
for t in threads:
	t.start()
live = sys.stdout.isatty()
if live:
	sys.stdout.write('\x1b[?1049h\x1b[?25l')
try:
	while proc.poll() is None:
		if live:
			with lock:
				frame = render(time.monotonic() - t0, shutil.get_terminal_size((160, 50)).lines - 3)
			sys.stdout.write('\x1b[H\x1b[2J' + frame)
			sys.stdout.flush()
		time.sleep(0.5)
finally:
	if live:
		sys.stdout.write('\x1b[?25h\x1b[?1049l')
for t in threads:
	t.join()
log.close()
print(render(time.monotonic() - t0, None))
print('█ done  ▒ emitted something, still going  ░ started, no artifact yet', file=sys.stderr)
print(f'log: {log.name}', file=sys.stderr)
if proc.returncode:
	print(subprocess.run(['tail', '-n', '40', log.name], capture_output=True, text=True).stdout, file=sys.stderr)
sys.exit(proc.returncode)
