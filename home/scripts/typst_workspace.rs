#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
miette = { version = "7", features = ["fancy"] }
serde_json = "1.0"
---

//! Builds the sway layout for a typst writing session out of a `typst_workspace.nix`
//! sitting in the current directory:
//!
//! ```text
//! workspace (splith)
//! ├── T  nvim <src> -c TypstWatch                    60%
//! └── C0 splitv                                      40%
//!     ├── C1 tabbed  ← docs[0..n]                    50%
//!     └── P  typst-out viewer                        50%
//! ```
//!
//! Every step anchors on a leaf con_id, never on a container: `move to mark` inserts
//! as a sibling of the marked container, and on a container the insert-as-child vs
//! insert-as-sibling choice would not be ours to make.
//!
//! Nothing in the sequence reads the focused container, so switching workspaces
//! while it runs cannot misplace anything.

use std::{
	collections::HashSet,
	io::{BufRead, BufReader},
	os::unix::process::CommandExt,
	path::{Path, PathBuf},
	process::{Child, Command, Stdio},
	sync::mpsc,
	time::{Duration, Instant},
};

use miette::{Result, miette};
use serde_json::Value;

const CONFIG: &str = "typst_workspace.nix";
const MARK: &str = "_typst_workspace";

/// ponytail: hardcoded split ratios, add config knobs when one is actually wanted
const DOCS_WIDTH_PPT: u32 = 40;

const SPAWN_TIMEOUT: Duration = Duration::from_secs(15);
/// A doc that does not compile means no viewer ever arrives.
const PLACE_TIMEOUT: Duration = Duration::from_secs(120);

const EXAMPLE: &str = r#"{
  src = "main.typ";
  docs = [ "../refs/stoch_1.pdf" "/abs/path/other.pdf" ];
}

Strings, not path literals — a path literal risks being copied to the nix store.
Relative entries resolve against this directory."#;

fn main() -> Result<()> {
	let args: Vec<String> = std::env::args().skip(1).collect();
	match args.as_slice() {
		[] => build(),
		[flag, p, t, ws] if flag == "--_place" => place(id_arg(p)?, id_arg(t)?, ws),
		_ => Err(miette!("typst_workspace takes no arguments")),
	}
}

fn id_arg(s: &str) -> Result<i64> { s.parse().map_err(|e| miette!("`{s}` is not a con_id: {e}")) }

// --- swaymsg -----------------------------------------------------------------

fn swaymsg(args: &[&str]) -> Result<Vec<u8>> {
	let out = Command::new("swaymsg").args(args).output().map_err(|e| miette!("failed to run swaymsg: {e}"))?;
	if !out.status.success() {
		return Err(miette!(
			help = String::from_utf8_lossy(&out.stderr).trim().to_owned(),
			"`swaymsg {}` failed",
			args.join(" ")
		));
	}
	Ok(out.stdout)
}

fn cmd(c: &str) -> Result<()> {
	let reply: Value = serde_json::from_slice(&swaymsg(&[c])?).map_err(|e| miette!("swaymsg reply is not JSON: {e}"))?;
	let results = reply.as_array().ok_or_else(|| miette!("swaymsg reply is not an array: {reply}"))?;
	for r in results {
		if r["success"] != true {
			return Err(miette!("sway rejected `{c}`: {}", r["error"]));
		}
	}
	Ok(())
}

fn tree() -> Result<Value> {
	serde_json::from_slice(&swaymsg(&["-t", "get_tree"])?).map_err(|e| miette!("get_tree is not JSON: {e}"))
}

fn children(n: &Value) -> Vec<&Value> {
	["nodes", "floating_nodes"].iter().filter_map(|k| n[*k].as_array()).flatten().collect()
}

// --- window watch ------------------------------------------------------------

/// A live `window` + `tick` subscription. `tick` is subscribed only for its
/// `"first": true` event, which sway emits on subscribe and which is the only
/// signal that the subscription is up — every spawn below races it.
struct Watch {
	proc: Child,
	rx: mpsc::Receiver<Option<i64>>,
}

impl Watch {
	fn start() -> Result<Self> {
		let mut proc = Command::new("swaymsg")
			.args(["-t", "subscribe", "-m", r#"["window","tick"]"#])
			.stdout(Stdio::piped())
			.stderr(Stdio::null())
			.spawn()
			.map_err(|e| miette!("failed to run swaymsg: {e}"))?;
		let out = proc.stdout.take().expect("piped just above");
		let (tx, rx) = mpsc::channel();
		std::thread::spawn(move || {
			for line in BufReader::new(out).lines().map_while(std::io::Result::ok) {
				let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
				let ev = if v["change"] == "new" {
					match v["container"]["id"].as_i64() {
						Some(id) => Some(id),
						None => continue,
					}
				} else if v.get("first").is_some() {
					None
				} else {
					continue;
				};
				if tx.send(ev).is_err() {
					break;
				}
			}
		});
		let watch = Self { proc, rx };
		loop {
			match watch.rx.recv_timeout(Duration::from_secs(5)) {
				Ok(None) => return Ok(watch),
				Ok(Some(_)) => continue,
				Err(_) => return Err(miette!("`swaymsg -t subscribe` never acknowledged")),
			}
		}
	}

	fn drain(&self) {
		while self.rx.try_recv().is_ok() {}
	}

	fn next_window(&self, timeout: Duration) -> Option<i64> {
		let deadline = Instant::now() + timeout;
		loop {
			match self.rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
				Ok(Some(id)) => return Some(id),
				Ok(None) => continue,
				Err(_) => return None,
			}
		}
	}

	/// Launches via `swaymsg exec` so sway owns the process: spawning it ourselves
	/// would leave it parented to the nvim we are about to exec into, holding that
	/// terminal's stdio and its controlling tty.
	///
	/// sway drops a new window wherever focus happens to be, so the window is placed
	/// afterwards by `move to mark` rather than by focusing `anchor` beforehand — a
	/// workspace switch mid-run then costs a flicker instead of the whole layout.
	fn open(&self, anchor: i64, target: &str) -> Result<i64> {
		mark(anchor)?;
		self.drain();
		cmd(&format!("exec {target}"))?;
		let id = self
			.next_window(SPAWN_TIMEOUT)
			.ok_or_else(|| miette!("no window appeared for `{target}` within {}s", SPAWN_TIMEOUT.as_secs()))?;
		cmd(&format!("[con_id={id}] move container to mark {MARK}"))?;
		Ok(id)
	}
}

fn mark(id: i64) -> Result<()> {
	cmd(&format!("unmark {MARK}"))?;
	cmd(&format!("[con_id={id}] mark --add {MARK}"))
}

fn focused_workspace() -> Result<String> {
	let v: Value = serde_json::from_slice(&swaymsg(&["-t", "get_workspaces"])?)
		.map_err(|e| miette!("get_workspaces is not JSON: {e}"))?;
	v.as_array()
		.ok_or_else(|| miette!("get_workspaces is not an array"))?
		.iter()
		.find(|w| w["focused"] == true)
		.and_then(|w| w["name"].as_str())
		.map(str::to_owned)
		.ok_or_else(|| miette!("no focused workspace"))
}

impl Drop for Watch {
	fn drop(&mut self) {
		let _ = self.proc.kill(); // already-exited swaymsg is not a failure worth reporting
	}
}

fn sh_quote(p: &Path) -> String { format!("'{}'", p.to_string_lossy().replace('\'', r"'\''")) }

// --- locating the terminal we were launched from -----------------------------

fn add_ancestor_chain(mut pid: i64, pids: &mut HashSet<i64>) -> Result<()> {
	while pid > 1 {
		pids.insert(pid);
		let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).map_err(|e| miette!("/proc/{pid}/stat: {e}"))?;
		// comm is parenthesised and may contain spaces and parens itself; ppid is the
		// second field after the last ')'
		let tail = stat.rsplit_once(')').ok_or_else(|| miette!("/proc/{pid}/stat: no comm field"))?.1;
		pid = tail
			.split_whitespace()
			.nth(1)
			.and_then(|s| s.parse().ok())
			.ok_or_else(|| miette!("/proc/{pid}/stat: no ppid field"))?;
	}
	Ok(())
}

fn ancestor_pids() -> Result<HashSet<i64>> {
	let mut pids = HashSet::new();
	add_ancestor_chain(i64::from(std::process::id()), &mut pids)?;

	// tmux detaches the pane shell from the terminal's process tree. Follow only
	// the client displaying this pane; following every client would select another
	// terminal when the same server has multiple attached sessions.
	if std::env::var_os("TMUX").is_some() {
		let pane = std::env::var("TMUX_PANE").map_err(|e| miette!("TMUX_PANE is unavailable: {e}"))?;
		let pane_location = String::from_utf8(
			Command::new("tmux")
				.args(["display-message", "-p", "-t", &pane, "#{session_name} #{window_index}"])
				.output()
				.map_err(|e| miette!("failed to find the tmux pane: {e}"))?
				.stdout,
		)
		.map_err(|e| miette!("tmux returned non-UTF-8 pane data: {e}"))?
		.trim()
		.to_owned();
		let output = Command::new("tmux")
			.args(["list-clients", "-F", "#{client_pid} #{client_session} #{client_window_index}"])
			.output()
			.map_err(|e| miette!("failed to find the tmux client: {e}"))?;
		if !output.status.success() {
			return Err(miette!("tmux could not list its clients"));
		}
		let clients = String::from_utf8_lossy(&output.stdout);
		let client = clients
			.lines()
			.find_map(|line| {
				let mut fields = line.split_whitespace();
				let pid = fields.next()?;
				let session = fields.next()?;
				let window = fields.next()?;
				(session == pane_location.split_once(' ')?.0
					&& window == pane_location.split_once(' ')?.1)
					.then_some(pid)
			})
			.ok_or_else(|| miette!("no tmux client displays pane {pane} in {pane_location}"))?;
		let pid = client.parse().map_err(|e| miette!("tmux returned invalid client pid `{client}`: {e}"))?;
		add_ancestor_chain(pid, &mut pids)?;
	}
	Ok(pids)
}

/// The sway view whose pid is in our own ppid chain, plus the workspace holding it.
/// Beats "focused workspace", which is wrong the moment this is launched from elsewhere.
fn locate<'a>(node: &'a Value, ws: Option<&'a Value>, pids: &HashSet<i64>) -> Option<(i64, &'a Value)> {
	let ws = if node["type"] == "workspace" { Some(node) } else { ws };
	if let Some(pid) = node["pid"].as_i64()
		&& pids.contains(&pid)
	{
		return Some((node["id"].as_i64()?, ws?));
	}
	children(node).into_iter().find_map(|c| locate(c, ws, pids))
}

fn leaf_titles(node: &Value, out: &mut Vec<String>) {
	let kids = children(node);
	if kids.is_empty() {
		if node["type"] == "con" || node["type"] == "floating_con" {
			out.push(node["name"].as_str().unwrap_or("<unnamed>").to_owned());
		}
		return;
	}
	for k in kids {
		leaf_titles(k, out);
	}
}

// --- config ------------------------------------------------------------------

fn read_config(cwd: &Path) -> Result<(PathBuf, Vec<PathBuf>)> {
	let path = cwd.join(CONFIG);
	if !path.is_file() {
		return Err(miette!(help = EXAMPLE, "no {CONFIG} in {}", cwd.display()));
	}

	let out = Command::new("nix")
		.args(["eval", "--json", "--file"])
		.arg(&path)
		.output()
		.map_err(|e| miette!("failed to run nix: {e}"))?;
	if !out.status.success() {
		return Err(miette!(help = String::from_utf8_lossy(&out.stderr).trim().to_owned(), "`nix eval` on {CONFIG} failed"));
	}

	let v: Value = serde_json::from_slice(&out.stdout).map_err(|e| miette!("`nix eval` output is not JSON: {e}"))?;
	let obj = v.as_object().ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG} must evaluate to an attrset, got {v}"))?;
	if let Some(k) = obj.keys().find(|k| *k != "src" && *k != "docs") {
		return Err(miette!(help = EXAMPLE, "unknown key `{k}` in {CONFIG}"));
	}

	let src = obj
		.get("src")
		.and_then(Value::as_str)
		.ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG}: `src` is missing or not a string"))?;
	let docs = obj
		.get("docs")
		.and_then(Value::as_array)
		.ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG}: `docs` is missing or not a list"))?
		.iter()
		.map(|d| {
			d.as_str()
				.map(|s| cwd.join(s))
				.ok_or_else(|| miette!("{CONFIG}: docs entry {d} is not a string"))
		})
		.collect::<Result<Vec<_>>>()?;
	if docs.is_empty() {
		return Err(miette!(help = EXAMPLE, "{CONFIG}: `docs` is empty — nothing to lay out beside the source"));
	}

	let src = cwd.join(src);
	let missing: Vec<String> = std::iter::once(&src)
		.chain(&docs)
		.filter(|p| !p.exists())
		.map(|p| p.display().to_string())
		.collect();
	if !missing.is_empty() {
		return Err(miette!("{CONFIG} points at files that do not exist:\n{}", missing.join("\n")));
	}

	Ok((src, docs))
}

// --- build -------------------------------------------------------------------

fn build() -> Result<()> {
	if std::env::var_os("SWAYSOCK").is_none() {
		return Err(miette!("SWAYSOCK is unset — typst_workspace drives sway over its IPC socket"));
	}
	let cwd = std::env::current_dir().map_err(|e| miette!("cannot read cwd: {e}"))?;
	let (src, docs) = read_config(&cwd)?;

	let pids = ancestor_pids()?;
	let root = tree()?;
	let (term, ws) =
		locate(&root, None, &pids).ok_or_else(|| miette!("none of our parent processes owns a sway window"))?;
	let ws_name = ws["name"].as_str().unwrap_or("?").to_owned();

	let mut titles = Vec::new();
	leaf_titles(ws, &mut titles);
	let floating = ws["floating_nodes"].as_array().map_or(0, Vec::len);
	if titles.len() != 1 || floating != 0 {
		return Err(miette!(
			help = "move to an empty workspace and re-run",
			"workspace `{ws_name}` already holds {} windows:\n{}",
			titles.len(),
			titles.join("\n")
		));
	}

	let watch = Watch::start()?;

	// normalises a workspace left in splitv by whatever was there before
	cmd(&format!("[con_id={term}] layout splith"))?;

	let z1 = watch.open(term, &format!("xdg-open {}", sh_quote(&docs[0])))?;
	cmd(&format!("[con_id={z1}] resize set width {DOCS_WIDTH_PPT} ppt"))?;
	cmd(&format!("[con_id={z1}] splitv"))?;

	// The typst viewer is spawned by `typst watch --open` from inside nvim, seconds
	// after we are gone, and lands next to whatever has focus then. A throwaway window
	// holds its slot; `--_place` swaps it out. sway 1.11 has no `append_layout`, so a
	// declarative layout with swallow criteria is not on the table.
	let placeholder = watch.open(z1, "zathura")?;

	if docs.len() > 1 {
		cmd(&format!("[con_id={z1}] splith"))?;
		let mut prev = z1;
		for d in &docs[1..] {
			prev = watch.open(prev, &format!("xdg-open {}", sh_quote(d)))?;
		}
		cmd(&format!("[con_id={z1}] layout tabbed"))?;
	}

	cmd(&format!("unmark {MARK}"))?;
	if focused_workspace()? == ws_name {
		cmd(&format!("[con_id={term}] focus"))?;
	}
	drop(watch);

	let exe = std::env::current_exe().map_err(|e| miette!("cannot find own path: {e}"))?;
	Command::new(exe)
		.args(["--_place", &placeholder.to_string(), &term.to_string(), &ws_name])
		.stdin(Stdio::null())
		.stdout(Stdio::null())
		.stderr(Stdio::null())
		.process_group(0)
		.spawn()
		.map_err(|e| miette!("failed to spawn the placeholder swap: {e}"))?;

	let e = Command::new("fish").arg("-c").arg(format!("e {} -c TypstWatch", sh_quote(&src))).exec();
	Err(miette!("exec fish: {e}"))
}

/// ponytail: takes the *first* new window on the machine, not one matched by title —
/// anything opened in that 1-3s gap steals the slot. Upgrade path is matching
/// `app_id`/`name` against the expected output pdf.
fn place(placeholder: i64, term: i64, ws_name: &str) -> Result<()> {
	let watch = Watch::start()?;
	if let Some(viewer) = watch.next_window(PLACE_TIMEOUT) {
		cmd(&format!("[con_id={viewer}] swap container with con_id {placeholder}"))?;
		cmd(&format!("[con_id={placeholder}] kill"))?;
		// minutes may have passed; only take the caret if that workspace is still the one in view
		if focused_workspace()? == ws_name {
			cmd(&format!("[con_id={term}] focus"))?;
		}
	} else {
		cmd(&format!("[con_id={placeholder}] kill"))?;
	}
	Ok(())
}
