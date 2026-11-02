// Accounts are ~/.claude/accounts/<name>/: `.credentials.json` (the login) and `meta.json` (usage snapshot).
// `current` links the account every claude runs on; each process follows it in place. Loaded through the hooks
// patch-claude-accounts.py splices into the binary, which also fills in the internals below.
import fs from "node:fs";
import path from "node:path";
import { isMainThread } from "node:worker_threads";

const KEY = "CLAUDE_SECURESTORAGE_CONFIG_DIR";
const root = path.join(process.env.HOME, ".claude/accounts");
const current = path.join(root, "current");
const hm = { hour: "2-digit", minute: "2-digit", hour12: false };

let internals;
const load = () => internals ??= (async () => {
	// @@internals@@
})();

async function get(endpoint, token) {
	const r = await fetch(`https://api.anthropic.com/api/oauth/${endpoint}`, {
		headers: { Authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" },
		signal: AbortSignal.timeout(3000),
	});
	if (!r.ok) throw Error(`${endpoint}: HTTP ${r.status}`);
	return r.json();
}

// live only while the access token is: refreshing it from here would race the lock of whichever process owns the account
async function meta(account) {
	const file = path.join(account, "meta.json");
	const cached = () => fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : undefined;
	const oauth = JSON.parse(fs.readFileSync(path.join(account, ".credentials.json"), "utf8")).claudeAiOauth;
	if (!(oauth.expiresAt > Date.now())) return cached();
	try {
		const [usage, profile] = await Promise.all([get("usage", oauth.accessToken), get("profile", oauth.accessToken)]);
		const m = { email: profile.account.email, usage, fetchedAt: Date.now() };
		fs.writeFileSync(file, JSON.stringify(m));
		return { ...m, live: true };
	} catch (e) {
		return { ...cached(), error: e.message };
	}
}

function option(name, m) {
	const now = Date.now();
	const windows = [["5h", m?.usage?.five_hour], ["week", m?.usage?.seven_day]].filter(([, w]) => w).map(([label, w]) => {
		const reset = w.resets_at && Date.parse(w.resets_at);
		return reset && reset <= now ? { label, left: 100 } : { label, left: Math.max(0, 100 - w.utilization), reset };
	});
	const binding = windows.filter((w) => w.reset).sort((a, b) => a.left - b.left)[0];
	const parts = [`Switch all to account ${name}${m?.email ? ` (${m.email})` : ""}`];
	if (windows.length) parts.push(windows.map((w) => `${w.label} ${Math.round(w.left)}% left`).join(" · ")
		+ (binding ? `, resets ${new Date(binding.reset).toLocaleString("en-US", { month: "short", day: "numeric", ...hm })}` : ""));
	else parts.push("usage unknown");
	if (m?.error) parts.push(`stale: ${m.error}`);
	else if (m && !m.live) parts.push(`as of ${new Date(m.fetchedAt).toLocaleTimeString("en-US", hm)}`);
	return { label: parts.join(" · "), value: `acct:${name}`, disabled: !!m?.live && windows.some((w) => w.left <= 0 && w.reset) };
}

export async function options() {
	const here = fs.realpathSync(process.env[KEY]);
	const names = fs.readdirSync(root).filter((n) => n !== "current" && fs.realpathSync(path.join(root, n)) !== here).sort((a, b) => a.localeCompare(b, "en", { numeric: true }));
	return Promise.all(names.map(async (name) => {
		if (!fs.existsSync(path.join(root, name, ".credentials.json"))) return { label: `Account ${name}: not logged in`, value: `acct:${name}`, disabled: true };
		try {
			return option(name, await meta(path.join(root, name)));
		} catch (e) {
			return { label: `Account ${name}: ${e.message}`, value: `acct:${name}`, disabled: true };
		}
	}));
}

let queue = Promise.resolve();
// moves this process onto `current`; serialized, as the menu and the watcher both trigger it
function follow(io = {}) {
	const step = async () => {
		const from = process.env[KEY], to = fs.realpathSync(current);
		if (fs.realpathSync(from) === to) return;
		const { mle, Nn, DI, uVe, Kn } = await load();
		await mle(io); // settles this process's own refresh under the departing account's lock
		await meta(from);
		process.env[KEY] = to;
		DI();
		try {
			await mle(io);
			const token = Nn();
			if (!token?.accessToken || !(token.expiresAt > Date.now())) throw Error(`no usable login in ${to}`);
		} catch (e) {
			process.env[KEY] = from;
			DI();
			throw e;
		}
		// uVe installs a login the way /login's OAuth step leaves it: wipes the store, then writes the token back. This token is
		// already stored, and shared with every claude on the account: the wipe would log them out, the write could undo their refresh.
		const store = Kn(), mutate = store.mutate;
		store.mutate = (update, c) => {
			const probe = { claudeAiOauth: {} };
			return update(probe).claudeAiOauth === probe.claudeAiOauth ? mutate.call(store, update, c) : Promise.resolve({ success: true });
		};
		try {
			await uVe(Nn(), io);
		} finally {
			store.mutate = mutate;
		}
	};
	return queue = queue.then(step, step); // a failed step was already reported to whoever awaited it
}

export function watch() {
	if (!isMainThread) return; // workers load the hook module too, and keep no login of their own
	if (!process.env[KEY]) return; // not launched onto an account, e.g. `claude -p` under an env token, which outranks any account anyway
	fs.watch(root, (_, file) => file === "current" && follow()).unref();
}

function link(name) {
	fs.symlinkSync(name, `${current}.${process.pid}`);
	fs.renameSync(`${current}.${process.pid}`, current);
}

// what /login does after its OAuth step, with the step replaced by moving every claude onto another account
export async function switchTo(name, ctx, done) {
	if (typeof ctx.setAppState !== "function") throw Error("menu context carries no setAppState");
	ctx.cancelRateLimitAutoQueueContinue?.();
	const { wn, Br, kAe } = await load();
	const account = wn();
	const previousAccount = account && { accountUuid: account.accountUuid, organizationUuid: account.organizationUuid };
	const previousGatewayAuth = Br();
	const prev = fs.readlinkSync(current);
	link(name);
	try {
		await follow({ credentials: ctx.credentials, storageV5: ctx.storageV5 });
	} catch (e) {
		link(prev);
		throw e;
	}
	const r = await kAe(ctx, true, { setAppState: ctx.setAppState, previousAccount, previousGatewayAuth });
	if (r.relaunching || r.gatewayLoginError !== undefined) throw Error(`post-login hooks: ${JSON.stringify(r)}`);
	done(`Switched every claude to account ${name} (${wn()?.emailAddress})`, { display: "system", shouldQuery: true });
}
