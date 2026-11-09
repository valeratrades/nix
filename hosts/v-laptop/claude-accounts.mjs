// Accounts are ~/.claude/accounts/<name>/, owned by ask_llm (its docs/ARCHITECTURE.md#claude-accounts): it relinks
// `current` and `running`, and labels each account. What stays here is the in-process part: each claude follows `running` in place.
// Loaded through the hooks patch-claude-accounts.py splices into the binary, which also fills in the internals below.
import fs from "node:fs";
import path from "node:path";
import { isMainThread } from "node:worker_threads";

const KEY = "CLAUDE_SECURESTORAGE_CONFIG_DIR";
const root = path.join(process.env.HOME, ".claude/accounts");
const AUTO = @auto_accounts@;
const AUTO_OFF = path.join(process.env.HOME, ".local/state/claude-auto-rotate-off"); // `cl auto off`

let internals;
const load = () => internals ??= (async () => {
	/* INTERNALS */
})();

async function claudeAccount(...args) {
	const p = Bun.spawn(["@ask_llm@", "dev", "claude-account", ...args], { stdout: "pipe", stderr: "pipe" });
	const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
	if (code !== 0) throw Error(`ask_llm dev claude-account ${args.join(" ")}: ${err.trim()}`);
	return out.trim();
}

export async function options() {
	const here = fs.realpathSync(process.env[KEY]);
	const all = (await claudeAccount("list", "--json")).split("\n").filter(Boolean).map((l) => JSON.parse(l));
	const unknown = AUTO.filter((e) => !all.some((a) => a.email === e));
	if (unknown.length) throw Error(`auto-rotated accounts not logged in here: ${unknown.join(", ")}`);
	const me = all.find((a) => a.dir === here);
	if (!me) throw Error(`${here} is not among the accounts`);
	const others = all.filter((a) => a !== me);
	const ahead = AUTO.includes(me.email) && !fs.existsSync(AUTO_OFF) ? AUTO.slice(AUTO.indexOf(me.email) + 1) : [];
	return [...ahead.flatMap((e) => others.filter((a) => a.email === e)), ...others.filter((a) => !ahead.includes(a.email))]
		.map((a) => ({ label: `Switch all to ${a.label}`, value: `acct:${a.name}`, disabled: a.disabled, auto: ahead.includes(a.email) }));
}

let queue = Promise.resolve();
// moves this process onto `dir`, else `running`; serialized, as the menu and the watcher both trigger it
function follow(io = {}, dir) {
	const step = async () => {
		const from = process.env[KEY], to = dir ?? await claudeAccount("running");
		if (fs.realpathSync(from) === to) return;
		const { mle, Nn, DI, uVe, Kn } = await load();
		await mle(io); // settles this process's own refresh under the departing account's lock
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
	fs.watch(root, (_, file) => file === "running" && follow()).unref();
}

// what /login does after its OAuth step, with the step replaced by moving every claude onto another account;
// `ctx.alone`: only this claude and new ones, keeping the others' prompt caches
export async function switchTo(name, ctx, done) {
	const { alone } = ctx;
	if (typeof ctx.setAppState !== "function") throw Error("menu context carries no setAppState");
	ctx.cancelRateLimitAutoQueueContinue?.();
	const { wn, Br, kAe } = await load();
	const account = wn();
	const previousAccount = account && { accountUuid: account.accountUuid, organizationUuid: account.organizationUuid };
	const previousGatewayAuth = Br();
	const [prevRunning, prevCurrent] = ["running", "current"].map((l) => fs.readlinkSync(path.join(root, l)));
	await claudeAccount("rotate", ...(alone ? ["--new"] : []), name);
	try {
		await follow({ credentials: ctx.credentials, storageV5: ctx.storageV5 }, alone ? fs.realpathSync(path.join(root, name)) : undefined);
	} catch (e) {
		if (!alone) await claudeAccount("rotate", prevRunning);
		await claudeAccount("rotate", "--new", prevCurrent);
		throw e;
	}
	const r = await kAe(ctx, true, { setAppState: ctx.setAppState, previousAccount, previousGatewayAuth });
	if (r.relaunching || r.gatewayLoginError !== undefined) throw Error(`post-login hooks: ${JSON.stringify(r)}`);
	done(`Switched ${alone ? "this and new claudes" : "every claude"} to account ${name} (${wn()?.emailAddress})`, { display: "system", shouldQuery: true });
}
