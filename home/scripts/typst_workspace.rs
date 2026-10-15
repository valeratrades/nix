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
//! ├── T  nvim -p <srcs> -c 'tabdo TypstWatch'       60%
//! └── C0 splitv                                      40%
//!     ├── C1 tabbed  ← docs[0..n]                    50%
//!     └── P  tabbed  ← typst-out viewer per src      50%
//! ```
//!
//! `srcs.focus` / `docs.focus` (0-based, as nix's `elemAt`) pick the tab each lands on.
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
  srcs = [ ./main.typ ./appendix.typ ]; # shorthand for `srcs.files`
  docs = {
    files = [ ../refs/stoch_1.pdf /abs/path/other.pdf ];
    focus = 1;  # 0-based; omitted means the first
  };
}"#;

struct Scope {
	files: Vec<PathBuf>,
	focus: usize,
}

fn main() -> Result<()> {
	let args: Vec<String> = std::env::args().skip(1).collect();
	match args.as_slice() {
		[] => build(),
		[flag, t, ws, sel, slots @ ..] if flag == "--_place" => place(id_arg(t)?, ws, id_arg(sel)?, slots),
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

enum Event {
	Subscribed,
	Window { id: i64, name: String, new: bool },
}

/// A live `window` + `tick` subscription. `tick` is subscribed only for its
/// `"first": true` event, which sway emits on subscribe and which is the only
/// signal that the subscription is up — every spawn below races it.
struct Watch {
	proc: Child,
	rx: mpsc::Receiver<Event>,
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
				let ev = if v["change"] == "new" || v["change"] == "title" {
					let Some(id) = v["container"]["id"].as_i64() else { continue };
					let name = v["container"]["name"].as_str().unwrap_or_default().to_owned(); // untitled yet; a `title` event follows
					Event::Window { id, name, new: v["change"] == "new" }
				} else if v.get("first").is_some() {
					Event::Subscribed
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
				Ok(Event::Subscribed) => return Ok(watch),
				Ok(Event::Window { .. }) => continue,
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
				Ok(Event::Window { id, new: true, .. }) => return Some(id),
				Ok(_) => continue,
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

fn xdg_dir(var: &str, fallback: &str) -> Result<PathBuf> {
	if let Some(v) = std::env::var_os(var) {
		return Ok(PathBuf::from(v));
	}
	let home = std::env::var_os("HOME").ok_or_else(|| miette!("neither {var} nor HOME is set"))?;
	Ok(PathBuf::from(home).join(fallback))
}

/// zathura takes no per-invocation `set`, so the only way to read the refs on white
/// while keeping the real keymap is a config dir that includes it and flips recolor back.
fn zathura_light_dir() -> Result<PathBuf> {
	let rc = xdg_dir("XDG_CONFIG_HOME", ".config")?.join("zathura/zathurarc");
	let dir = xdg_dir("XDG_CACHE_HOME", ".cache")?.join("typst_workspace/zathura-light");
	std::fs::create_dir_all(&dir).map_err(|e| miette!("cannot create {}: {e}", dir.display()))?;
	let contents = format!("include {}\nset recolor false\n", rc.display());
	std::fs::write(dir.join("zathurarc"), contents).map_err(|e| miette!("cannot write {}/zathurarc: {e}", dir.display()))?;
	Ok(dir)
}

// --- locating the terminal we were launched from -----------------------------

fn add_ancestor_pids(mut pid: i64, pids: &mut HashSet<i64>) -> Result<()> {
	while pid > 1 {
		pids.insert(pid);
		let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).map_err(|e| miette!("/proc/{pid}/stat: {e}"))?;
		let tail = stat.rsplit_once(')').ok_or_else(|| miette!("/proc/{pid}/stat: no comm field"))?.1;
		pid = tail.split_whitespace().nth(1).and_then(|s| s.parse().ok())
			.ok_or_else(|| miette!("/proc/{pid}/stat: no ppid field"))?;
	}
	Ok(())
}

fn ancestor_pids() -> Result<HashSet<i64>> {
	let mut pids = HashSet::new();
	add_ancestor_pids(i64::from(std::process::id()), &mut pids)?;
	if let Some(pane) = std::env::var_os("TMUX_PANE") {
		let pane = pane.to_string_lossy();
		let output = Command::new("tmux")
			.args(["display-message", "-p", "-t", &pane, "#{client_pid}"])
			.output()
			.map_err(|e| miette!("failed to identify the invoking terminal: {e}"))?;
		if output.status.success() {
			let pid = String::from_utf8_lossy(&output.stdout).trim().parse()
			.map_err(|e| miette!("tmux returned an invalid terminal pid: {e}"))?;
			add_ancestor_pids(pid, &mut pids)?;
		}
	}
	Ok(pids)
}

fn locate<'a>(node: &'a Value, ws: Option<&'a Value>, pids: &HashSet<i64>) -> Option<(i64, &'a Value)> {
	let ws = if node["type"] == "workspace" { Some(node) } else { ws };
	if node["pid"].as_i64().is_some_and(|pid| pids.contains(&pid)) {
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

fn read_config(cwd: &Path) -> Result<(Scope, Scope)> {
	let path = cwd.join(CONFIG);
	if !path.is_file() {
		return Err(miette!(help = EXAMPLE, "no {CONFIG} in {}", cwd.display()));
	}

	let out = Command::new("nix")
		.args(["eval", "--json", "--file"])
		.arg(&path)
		// `toString` of a path literal is its absolute path, no store copy
		.args(["--apply", "builtins.mapAttrs (_: s: if builtins.isList s then { files = map toString s; } else s // { files = map toString s.files; })"])
		.output()
		.map_err(|e| miette!("failed to run nix: {e}"))?;
	if !out.status.success() {
		return Err(miette!(help = String::from_utf8_lossy(&out.stderr).trim().to_owned(), "`nix eval` on {CONFIG} failed"));
	}

	let v: Value = serde_json::from_slice(&out.stdout).map_err(|e| miette!("`nix eval` output is not JSON: {e}"))?;
	let obj = v.as_object().ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG} must evaluate to an attrset, got {v}"))?;
	if let Some(k) = obj.keys().find(|k| *k != "srcs" && *k != "docs") {
		return Err(miette!(help = EXAMPLE, "unknown key `{k}` in {CONFIG}"));
	}

	let scope = |key: &str| -> Result<Scope> {
		let scope = obj.get(key).and_then(Value::as_object).ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG}: `{key}` is missing"))?;
		if let Some(k) = scope.keys().find(|k| *k != "files" && *k != "focus") {
			return Err(miette!(help = EXAMPLE, "unknown key `{key}.{k}` in {CONFIG}"));
		}
		let files = scope["files"]
			.as_array()
			.ok_or_else(|| miette!(help = EXAMPLE, "{CONFIG}: `{key}.files` is not a list"))?
			.iter()
			.map(|d| d.as_str().map(|s| cwd.join(s)).ok_or_else(|| miette!("{CONFIG}: {key} entry {d} is not a string")))
			.collect::<Result<Vec<_>>>()?;
		if files.is_empty() {
			return Err(miette!(help = EXAMPLE, "{CONFIG}: `{key}` is empty"));
		}
		let focus = match scope.get("focus") {
			None => 0,
			Some(v) => v
				.as_u64()
				.and_then(|i| usize::try_from(i).ok())
				.filter(|i| *i < files.len())
				.ok_or_else(|| miette!("{CONFIG}: `{key}.focus` = {v} is not an index into its {} files", files.len()))?,
		};
		Ok(Scope { files, focus })
	};
	let srcs = scope("srcs")?;
	let docs = scope("docs")?;

	let mut stems = HashSet::new();
	for s in &srcs.files {
		let stem = s.file_stem().ok_or_else(|| miette!("{CONFIG}: src `{}` has no file name", s.display()))?.to_string_lossy().into_owned();
		if !stems.insert(stem.clone()) {
			return Err(miette!("{CONFIG}: two srcs share the stem `{stem}` — their viewers would be indistinguishable"));
		}
	}

	let missing: Vec<String> = srcs
		.files
		.iter()
		.chain(&docs.files)
		.filter(|p| !p.exists())
		.map(|p| p.display().to_string())
		.collect();
	if !missing.is_empty() {
		return Err(miette!("{CONFIG} points at files that do not exist:\n{}", missing.join("\n")));
	}

	Ok((srcs, docs))
}

// --- build -------------------------------------------------------------------

fn build() -> Result<()> {
	if std::env::var_os("SWAYSOCK").is_none() {
		return Err(miette!("SWAYSOCK is unset — typst_workspace drives sway over its IPC socket"));
	}
	let cwd = std::env::current_dir().map_err(|e| miette!("cannot read cwd: {e}"))?;
	let (srcs, docs) = read_config(&cwd)?;

	let root = tree()?;
	let pids = ancestor_pids()?;
	let (term, ws) = locate(&root, None, &pids)
		.ok_or_else(|| miette!("none of our parent processes owns a sway window"))?;
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

	let light = zathura_light_dir()?;
	let doc_cmd = |d: &Path| format!("zathura -c {} {}", sh_quote(&light), sh_quote(d));

	let z1 = watch.open(term, &doc_cmd(&docs.files[0]))?;
	cmd(&format!("[con_id={z1}] resize set width {DOCS_WIDTH_PPT} ppt"))?;
	cmd(&format!("[con_id={z1}] splitv"))?;

	// Typst viewers are spawned by `typst watch --open` from inside nvim, seconds
	// after we are gone, and land next to whatever has focus then. A throwaway window
	// holds each slot; `--_place` swaps them out. sway 1.11 has no `append_layout`, so a
	// declarative layout with swallow criteria is not on the table.
	let p0 = watch.open(z1, "zathura")?;

	let tab = |first: i64, rest: Vec<String>| -> Result<Vec<i64>> {
		let mut ids = vec![first];
		if rest.is_empty() {
			return Ok(ids);
		}
		cmd(&format!("[con_id={first}] splith"))?;
		for target in rest {
			ids.push(watch.open(*ids.last().expect("seeded with first"), &target)?);
		}
		cmd(&format!("[con_id={first}] layout tabbed"))?;
		Ok(ids)
	};
	let doc_ids = tab(z1, docs.files[1..].iter().map(|d| doc_cmd(d)).collect())?;
	let placeholders = tab(p0, vec!["zathura".to_owned(); srcs.files.len() - 1])?;
	let viewer = placeholders[srcs.focus];

	cmd(&format!("unmark {MARK}"))?;
	// focusing is the only way to pick a tab, and it would drag us onto a workspace the user left
	if focused_workspace()? == ws_name {
		cmd(&format!("[con_id={}] focus", doc_ids[docs.focus]))?;
		cmd(&format!("[con_id={viewer}] focus"))?;
		cmd(&format!("[con_id={term}] focus"))?;
	}
	drop(watch);

	let slots = srcs.files.iter().zip(&placeholders).map(|(s, p)| {
		format!("{}={p}", s.file_stem().expect("checked in read_config").to_string_lossy())
	});
	let exe = std::env::current_exe().map_err(|e| miette!("cannot find own path: {e}"))?;
	Command::new(exe)
		.args(["--_place".to_owned(), term.to_string(), ws_name.clone(), viewer.to_string()])
		.args(slots)
		.stdin(Stdio::null())
		.stdout(Stdio::null())
		.stderr(Stdio::null())
		.process_group(0)
		.spawn()
		.map_err(|e| miette!("failed to spawn the placeholder swap: {e}"))?;

	let tab = srcs.focus + 1; // vim tabs count from 1
	let srcs = srcs.files.iter().map(|s| sh_quote(s)).collect::<Vec<_>>().join(" ");
	let e = Command::new("fish").arg("-c").arg(format!(r#"e -p {srcs} -c "'tabdo TypstWatch'" -c "'tabnext {tab}'""#)).exec(); // `e` evals its args, eating one layer of quotes
	Err(miette!("exec fish: {e}"))
}

/// Viewers are told apart by title: zathura titles a window with its file's path, and
/// typst names the output `<stem>.pdf`.
/// `selected` is the placeholder holding the slot whose tab should stay up; swaps reshuffle tab focus.
fn place(term: i64, ws_name: &str, mut selected: i64, slots: &[String]) -> Result<()> {
	let mut pending = slots
		.iter()
		.map(|s| {
			let (stem, p) = s.rsplit_once('=').ok_or_else(|| miette!("`{s}` is not a <stem>=<con_id> slot"))?;
			Ok((format!("{stem}.pdf"), id_arg(p)?))
		})
		.collect::<Result<Vec<_>>>()?;
	let watch = Watch::start()?;
	let deadline = Instant::now() + PLACE_TIMEOUT;
	while !pending.is_empty() {
		let Ok(ev) = watch.rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) else { break };
		let Event::Window { id: viewer, name, .. } = ev else { continue };
		let Some(i) = pending.iter().position(|(pdf, _)| name == *pdf || name.ends_with(&format!("/{pdf}"))) else { continue };
		let (_, placeholder) = pending.swap_remove(i);
		cmd(&format!("[con_id={viewer}] swap container with con_id {placeholder}"))?;
		cmd(&format!("[con_id={placeholder}] kill"))?;
		if placeholder == selected {
			selected = viewer;
		}
		// minutes may have passed; only take the caret if that workspace is still the one in view
		if focused_workspace()? == ws_name {
			cmd(&format!("[con_id={selected}] focus"))?;
			cmd(&format!("[con_id={term}] focus"))?;
		}
	}
	for (_, placeholder) in pending {
		cmd(&format!("[con_id={placeholder}] kill"))?;
	}
	Ok(())
}
