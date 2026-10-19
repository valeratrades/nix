// Journals one line of boot milestones, power button → visible Chrome tab loaded: `journalctl --user -t boot-timeline`.
// All points are seconds since kernel start (CLOCK_MONOTONIC); firmware/loader run before it.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert';

const port = process.argv[2];
assert(port, 'usage: boot_timeline.mjs <cdp-port>');

const run = (cmd, ...args) => execFileSync(cmd, args, { encoding: 'utf8' }).trim();
const sysProp = (prop, unit) => Number(run('systemctl', 'show', '-p', prop, '--value', ...(unit ? [unit] : []))) / 1e6;
const userProp = (prop, unit) => Number(run('systemctl', '--user', 'show', '-p', prop, '--value', unit)) / 1e6;
const clkTck = Number(run('getconf', 'CLK_TCK'));
const procStart = pid => Number(readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1].split(' ')[19]) / clkTck; // boottime, = monotonic unless suspended
const epochToMono = s => s - (Date.now() / 1000 - Number(process.hrtime.bigint()) / 1e9);

async function visibleTabTiming() {
  const tabs = (await (await fetch(`http://localhost:${port}/json`)).json()).filter(t => t.type === 'page');
  const expr = `JSON.stringify([document.visibilityState, performance.timeOrigin, performance.getEntriesByType("navigation")[0]?.loadEventEnd])`;
  const probe = t => new Promise(res => {
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    const timer = setTimeout(() => { ws.close(); res(null); }, 2000); // discarded/frozen tabs never answer
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true } }));
    ws.onmessage = m => { clearTimeout(timer); ws.close(); res(JSON.parse(m.data).result?.result?.value ?? null); };
    ws.onerror = () => { clearTimeout(timer); res(null); };
  });
  for (const [t, v] of (await Promise.all(tabs.map(async t => [t, await probe(t)])))) {
    if (!v) continue;
    const [vis, origin, loadEnd] = JSON.parse(v);
    if (vis === 'visible' && loadEnd > 0) return { url: t.url, nav: epochToMono(origin / 1000), load: epochToMono((origin + loadEnd) / 1000) };
  }
  return null;
}

let tab = null;
for (let i = 0; i < 300 && !tab; i++) {
  tab = await visibleTabTiming().catch(() => null); // CDP isn't listening until Chrome is up
  if (!tab) await new Promise(r => setTimeout(r, 1000));
}

const firmware = sysProp('FirmwareTimestampMonotonic') - sysProp('LoaderTimestampMonotonic');
const loader = sysProp('LoaderTimestampMonotonic');
const chromePid = run('pgrep', '-o', '-f', 'share/google/chrome/chrome');
const chromeExec = await (async () => { // the wrapper's pre-exec work (ext-settings sync) shows up as this histogram
  const { webSocketDebuggerUrl } = await (await fetch(`http://localhost:${port}/json/version`)).json();
  const ws = new WebSocket(webSocketDebuggerUrl);
  const msg = await new Promise((res, rej) => {
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Browser.getHistogram', params: { name: 'Startup.LoadTime.ProcessCreateToApplicationStart' } }));
    ws.onmessage = m => { ws.close(); res(JSON.parse(m.data)); };
    ws.onerror = rej;
  });
  const h = msg.result.histogram;
  assert.equal(h.count, 1, 'recorded once per browser process');
  return procStart(chromePid) + h.sum / 1000;
})();

const points = {
  initrd: sysProp('InitRDTimestampMonotonic'),
  userspace: sysProp('UserspaceTimestampMonotonic'),
  hm_start: sysProp('InactiveExitTimestampMonotonic', 'home-manager-v.service'),
  hm_done: sysProp('ActiveEnterTimestampMonotonic', 'home-manager-v.service'),
  getty: sysProp('ActiveEnterTimestampMonotonic', 'getty@tty1.service'),
  sway: procStart(run('pgrep', '-o', '-x', 'sway')),
  sway_session: userProp('ActiveEnterTimestampMonotonic', 'sway-session.target'),
  chrome_wrapper: procStart(chromePid), // ext-settings sync runs between this and chrome_exec
  chrome_exec: chromeExec,
  tab_nav: tab?.nav,
  tab_load: tab?.load,
};
const fmt = Object.entries(points).map(([k, v]) => `${k}=${v === undefined ? 'unobserved' : v.toFixed(2)}`).join(' ');
const total = tab ? (firmware + loader + tab.load).toFixed(1) : 'unobserved';
console.log(`power→tab_load=${total}s firmware=${firmware.toFixed(2)} loader=${loader.toFixed(2)} | ${fmt} | ${tab?.url ?? 'no visible tab finished loading within 300s'}`);
