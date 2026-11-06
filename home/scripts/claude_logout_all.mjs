// Signs every device out of the claude.ai account the live Chrome holds: revokes each app's OAuth token
// (Claude Code, Claude for Chrome, ...), then ends all web sessions, Chrome's own included.
// Runs inside a hidden Chrome tab: claude.ai's Cloudflare turns the same cookies away from any other client.
import assert from 'node:assert';

const [port, mode] = process.argv.slice(2);
assert(port && (mode === undefined || mode === '--dry-run'), 'usage: claude_logout_all.mjs <cdp-port> [--dry-run]');

async function inPage(dryRun) {
	const api = async (path, method = 'GET') => {
		const r = await fetch(path, { method });
		const body = await r.text();
		if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${body}`);
		return body && JSON.parse(body);
	};
	const lines = [];
	const subscriptions = (await api('/api/account')).memberships.map(m => m.organization).filter(o => o.capabilities.includes('chat')); // the rest are Console orgs, which hold no logins
	if (!subscriptions.length) throw new Error('no claude.ai organization on this account');
	for (const { uuid, name } of subscriptions) {
		const list = `/api/oauth/organizations/${uuid}/oauth_tokens`;
		const live = async () => (await api(list)).filter(t => !t.is_revoked);
		const tokens = await live();
		lines.push(...tokens.map(t => `${dryRun ? 'would revoke' : 'revoked'} ${name}: ${t.application_name} from ${t.created_at.slice(0, 10)}`));
		if (dryRun) continue;
		const failed = (await Promise.allSettled(tokens.map(t => api(`${list}/${t.id}/revoke`, 'POST')))).filter(r => r.status === 'rejected');
		const left = await live();
		if (left.length) throw new Error(`${name}: ${left.length} token(s) still live: ${failed.map(r => r.reason.message).join('; ')}`);
	}
	if (!dryRun) await api('/api/auth/logout/all-sessions', 'POST');
	return lines.join('\n');
}

const { webSocketDebuggerUrl } = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(webSocketDebuggerUrl);
const pending = new Map();
let nextId = 0;
ws.onmessage = e => {
	const m = JSON.parse(e.data);
	pending.get(m.id)?.(m);
};
await new Promise((ok, err) => { ws.onopen = ok; ws.onerror = err; });
const call = (method, params = {}, sessionId) => new Promise((ok, err) => {
	const id = ++nextId;
	pending.set(id, m => m.error ? err(new Error(`${method}: ${m.error.message}`)) : ok(m.result));
	ws.send(JSON.stringify({ id, method, params, sessionId }));
});

const { targetId } = await call('Target.createTarget', { url: 'https://claude.ai/robots.txt', background: true, hidden: true }); // static page: no SPA to redirect away once logged out
try {
	const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
	const evaluate = async expression => {
		const { result, exceptionDetails } = await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
		if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text);
		return result.value;
	};
	while (!(await evaluate(`location.origin === 'https://claude.ai' && document.readyState === 'complete'`))) await new Promise(r => setTimeout(r, 500));
	console.log(await evaluate(`(${inPage})(${mode === '--dry-run'})`));
} finally {
	await call('Target.closeTarget', { targetId });
	ws.close();
}
