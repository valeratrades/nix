#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[package]
edition = "2024"

[dependencies]
libc = "0.2"
serde_json = "1"
v_utils = { version = "2.25", default-features = false }
---

//! Live gantt of a cargo or nix build: one bar per crate and per derivation, redrawn as the build goes.
//! Crate starts are cargo's `Compiling` lines, ends its `compiler-artifact` json. Inside a nix build that json exists only
//! if the derivation's cargo got `--message-format=json-render-diagnostics` (`cargoBuildFlags`).

#[path = "shared/winsize.rs"]
mod winsize;

use std::{
	collections::{HashMap, VecDeque},
	fs::File,
	io::{BufRead, BufReader, BufWriter, Read, Write},
	os::unix::process::ExitStatusExt,
	process::{Command, Stdio},
	sync::mpsc::{self, RecvTimeoutError},
	time::{Duration, Instant},
};

use serde_json::Value;
use winsize::winsize;
use v_utils::chart::{Row, bar, gantt};

const USAGE: &str = "usage: build_gantt [sudo] cargo build|check|clippy|doc [args...]  (the plain subcommand: cargo-limit aliases eat the json)
       build_gantt [sudo] nix|nixos-rebuild [args...]";
const TAIL: usize = 40;
const REDRAW: Duration = Duration::from_millis(500);

#[derive(Clone, Copy, PartialEq)]
enum Mode {
	Cargo,
	Nix,
}

#[derive(Clone, Copy)]
enum Stream {
	Out,
	Err,
}

struct Span {
	label: String,
	phase: Option<String>,
	start: f64,
	end: Option<f64>,
	done: bool,
	act: Option<u64>,    // the derivation's build activity
	parent: Option<u64>, // the build activity of the derivation a crate is compiled in
}

struct Act {
	ty: u64,
	start: f64,
	stop: Option<f64>,
	bytes: u64,
}

#[derive(Default)]
struct State {
	spans: Vec<Span>,
	crates: HashMap<(Option<u64>, (String, String)), usize>,
	drvs: HashMap<u64, usize>,
	acts: HashMap<u64, Act>,
	shown: Vec<(Stream, String)>,
	hidden: VecDeque<String>, // the latest logged lines that aren't in `shown`
	status: String,
	last_nix: f64,
}

/// Terminates the child if anything panics: a dead reader leaves it blocked on a full pipe. TERM, since under `sudo` the
/// child is sudo, which relays TERM to the command but can't relay KILL.
struct Guard {
	pid: libc::pid_t,
	alt_screen: bool,
}
impl Drop for Guard {
	fn drop(&mut self) {
		if self.alt_screen {
			print!("\x1b[?25h\x1b[?1049l");
			std::io::stdout().flush().expect("stdout writable");
		}
		if std::thread::panicking() {
			unsafe { libc::kill(self.pid, libc::SIGTERM) };
		}
	}
}

impl State {
	fn line(&mut self, mode: Mode, stream: Stream, line: &str, now: f64, log: &mut impl Write) {
		if mode == Mode::Nix
			&& let Some(json) = line.strip_prefix("@nix ")
		{
			let ev: Value = serde_json::from_str(json).unwrap_or_else(|e| panic!("bad nix event {json}: {e}"));
			return self.nix_event(&ev, now, log);
		}
		if matches!(stream, Stream::Out) && line.starts_with("{\"reason\":") {
			return self.cargo_json(line, now, None);
		}
		writeln!(log, "{line}").expect("log writable");
		if mode == Mode::Cargo && self.compiling(line, now, None) {
			return self.hide(line);
		}
		if matches!(stream, Stream::Err) && (mode == Mode::Nix || line.starts_with("warning") || line.starts_with("error")) {
			self.status = one_line(line);
		}
		self.shown.push((stream, line.to_owned()));
	}

	fn hide(&mut self, line: &str) {
		if self.hidden.len() == TAIL {
			self.hidden.pop_front();
		}
		self.hidden.push_back(line.to_owned());
	}

	/// Other build output starts with `{` too (shell `{ ...; }` in Makefiles); only `{"reason":` lines are cargo's.
	fn cargo_json(&mut self, line: &str, now: f64, parent: Option<u64>) {
		let msg: Value = serde_json::from_str(line).unwrap_or_else(|e| panic!("bad cargo message {line}: {e}"));
		match msg["reason"].as_str() {
			Some("compiler-artifact") => {
				let id = msg["package_id"].as_str().expect("artifacts name their package");
				let Some(&i) = self.crates.get(&(parent, pkg_key(id))) else {
					return; // fresh: not compiled this run
				};
				let custom_build = msg["target"]["kind"].as_array().expect("targets list their kinds").iter().any(|k| k == "custom-build");
				let span = &mut self.spans[i];
				span.end = Some(now);
				span.done |= !custom_build && !id.starts_with("path+"); // a workspace member may still have bins to build
			}
			Some("build-finished") =>
				for span in self.spans.iter_mut().filter(|s| s.act.is_none() && s.parent == parent && s.end.is_some()) {
					span.done = true;
				},
			_ => {}
		}
	}

	/// `Compiling` is printed once per package, so a bar is a package, not a unit.
	fn compiling(&mut self, line: &str, now: f64, parent: Option<u64>) -> bool {
		let plain = strip_ansi(line);
		let mut words = plain.split_whitespace();
		let (Some("Compiling" | "Checking" | "Documenting"), Some(name), Some(ver)) = (words.next(), words.next(), words.next()) else {
			return false;
		};
		let Some(ver) = ver.strip_prefix('v') else {
			return false;
		};
		let key = (parent, (name.to_owned(), ver.to_owned()));
		if !self.crates.contains_key(&key) {
			self.crates.insert(key, self.spans.len());
			self.spans.push(Span {
				label: format!("{name} v{ver}"),
				phase: None,
				start: now,
				end: None,
				done: false,
				act: None,
				parent,
			});
		}
		true
	}

	fn nix_event(&mut self, ev: &Value, now: f64, log: &mut impl Write) {
		self.last_nix = now;
		let id = ev["id"].as_u64();
		let fields = &ev["fields"];
		match ev["action"].as_str().expect("nix events have an action") {
			"start" => {
				let (id, ty) = (id.expect("starts have an id"), ev["type"].as_u64().expect("starts have a type"));
				if ty == 105 {
					let drv = fields[0].as_str().expect("build starts name their drv").rsplit('/').next().expect("rsplit yields at least one part");
					let name = drv.split_once('-').expect("store names are <hash>-<name>").1.trim_end_matches(".drv");
					self.drvs.insert(id, self.spans.len());
					self.spans.push(Span {
						label: format!("[{name}]"),
						phase: None,
						start: now,
						end: None,
						done: false,
						act: Some(id),
						parent: None,
					});
				}
				self.acts.insert(id, Act { ty, start: now, stop: None, bytes: 0 });
			}
			"stop" => {
				let id = id.expect("stops have an id");
				self.acts.get_mut(&id).expect("stop follows its start").stop = Some(now);
				if let Some(&i) = self.drvs.get(&id) {
					let span = &mut self.spans[i];
					(span.end, span.done, span.phase) = (Some(now), true, None);
					for span in self.spans.iter_mut().filter(|s| s.parent == Some(id) && s.end.is_some()) {
						span.done = true;
					}
				}
			}
			"result" => {
				let id = id.expect("results have an id");
				match ev["type"].as_u64().expect("results have a type") {
					101 => {
						let line = fields[0].as_str().expect("log lines carry their text");
						writeln!(log, "{line}").expect("log writable");
						self.hide(line);
						let parent = self.drvs.contains_key(&id).then_some(id);
						if line.starts_with("{\"reason\":") {
							self.cargo_json(line, now, parent);
						} else {
							self.compiling(line, now, parent);
						}
					}
					104 =>
						if let Some(&i) = self.drvs.get(&id) {
							self.spans[i].phase = Some(fields[0].as_str().expect("phases are named").to_owned());
						},
					105 => {
						let act = self.acts.get_mut(&id).expect("progress follows its start");
						if act.ty == 101 {
							act.bytes = act.bytes.max(fields[0].as_u64().expect("progress counts bytes"));
						}
					}
					_ => {}
				}
			}
			"msg" => {
				let msg = ev["msg"].as_str().expect("msgs carry their text");
				writeln!(log, "{msg}").expect("log writable");
				self.shown.push((Stream::Err, msg.to_owned()));
				if ev["level"].as_u64().expect("msgs have a level") <= 1 {
					self.status = one_line(msg);
				}
			}
			_ => {}
		}
	}

	/// In display order, each with whether it's still running. Crates sit under the derivation they compile in; one that
	/// never reported an artifact (its cargo got no json flag) is open until its derivation ends.
	fn rows(&self, now: f64) -> Vec<(Row, bool)> {
		let row = |s: &Span, depth, until: Option<f64>| {
			let label = match &s.phase {
				Some(p) => format!("{} {p}", s.label),
				None => s.label.clone(),
			};
			let glyph = if s.done { '█' } else if s.end.is_some() { '▒' } else { '░' };
			let end = if s.done { s.end.expect("done spans have ended") } else { until.unwrap_or(now) };
			(Row { label, depth, start: s.start, end, glyph }, !s.done && until.is_none())
		};
		let mut out = Vec::new();
		let subs: Vec<&Act> = self.acts.values().filter(|a| a.ty == 108).collect();
		if !subs.is_empty() {
			let running = subs.iter().filter(|a| a.stop.is_none()).count();
			let bytes: u64 = self.acts.values().filter(|a| a.ty == 101).map(|a| a.bytes).sum();
			let start = subs.iter().map(|a| a.start).fold(f64::INFINITY, f64::min);
			let end = if running > 0 { now } else { subs.iter().filter_map(|a| a.stop).fold(0.0, f64::max) };
			let label = format!("substitute {}/{} paths, {}", subs.len() - running, subs.len(), human(bytes));
			out.push((Row { label, depth: 0, start, end, glyph: if running > 0 { '▒' } else { '█' } }, running > 0));
		}
		for top in self.spans.iter().filter(|s| s.parent.is_none()) {
			out.push(row(top, 0, None));
			if let Some(act) = top.act {
				let until = top.done.then(|| top.end.expect("done spans have ended"));
				out.extend(self.spans.iter().filter(|s| s.parent == Some(act)).map(|s| row(s, 1, until)));
			}
		}
		out
	}

	fn header(&self, now: f64) -> String {
		let count = |drv: bool| {
			let of: Vec<&Span> = self.spans.iter().filter(|s| s.act.is_some() == drv).collect();
			(of.iter().filter(|s| s.done).count(), of.len())
		};
		let mut h = format!("{now:6.1}s");
		for (what, (done, n)) in [("crates", count(false)), ("drvs", count(true))] {
			if n > 0 {
				h += &format!("  {done}/{n} {what} done");
			}
		}
		h
	}

	/// eval, substitute, build and the time after nix's last event (activation, for nixos-rebuild), from the activity log.
	fn summary(&self, total: f64) -> String {
		let iv = |ty: u64| -> Vec<(f64, f64)> { self.acts.values().filter(|a| a.ty == ty).map(|a| (a.start, a.stop.unwrap_or(self.last_nix))).collect() };
		let eval_end = self.acts.values().filter(|a| matches!(a.ty, 102 | 104 | 105 | 108)).map(|a| a.start).fold(self.last_nix, f64::min);
		let (subs, builds) = (iv(108), iv(105));
		let bytes: u64 = self.acts.values().filter(|a| a.ty == 101).map(|a| a.bytes).sum();
		let phases = [
			("eval", eval_end, String::new()),
			("substitute", union(subs.clone()), format!("{} paths, {}", subs.len(), human(bytes))),
			("build", union(builds.clone()), format!("{} drvs", builds.len())),
			("after nix", total - self.last_nix, String::new()),
		];
		let covered = union([(0.0, eval_end), (self.last_nix, total)].into_iter().chain(subs).chain(builds).collect());
		let mut out = String::new();
		for (name, secs, note) in &phases {
			out += format!("{name:<11}{:<40} {secs:>6.1}s  {note}", bar(secs / total, 40)).trim_end();
			out.push('\n');
		}
		let overlap = phases.iter().map(|p| p.1).sum::<f64>() - covered;
		out + &format!("total {total:.1}s; phase overlap {overlap:.1}s; unattributed {:.1}s", total - covered)
	}
}

fn pkg_key(package_id: &str) -> (String, String) {
	let (src, frag) = package_id.rsplit_once('#').expect("package ids end in #<fragment>");
	match frag.split_once('@') {
		Some((name, ver)) => (name.to_owned(), ver.to_owned()),
		// the name is omitted when it equals the source's last path segment
		None => {
			let path = src.split_once('?').map_or(src, |(p, _)| p).trim_end_matches('/');
			(path.rsplit('/').next().expect("rsplit yields at least one part").to_owned(), frag.to_owned())
		}
	}
}

fn union(mut iv: Vec<(f64, f64)>) -> f64 {
	iv.sort_by(|a, b| a.0.total_cmp(&b.0));
	let (mut total, mut reach) = (0.0, f64::MIN);
	for (s, e) in iv {
		total += (e - s.max(reach)).max(0.0);
		reach = reach.max(e);
	}
	total
}

fn human(b: u64) -> String {
	if b < 1 << 20 { format!("{:.1} KiB", b as f64 / 1024.0) } else { format!("{:.1} MiB", b as f64 / 1048576.0) }
}

fn one_line(s: &str) -> String {
	strip_ansi(s).split_whitespace().collect::<Vec<_>>().join(" ")
}

fn strip_ansi(s: &str) -> String {
	let mut out = String::with_capacity(s.len());
	let mut chars = s.chars();
	while let Some(c) = chars.next() {
		if c != '\x1b' {
			out.push(c);
		} else if chars.next() == Some('[') {
			for c in chars.by_ref() {
				if c.is_ascii_alphabetic() {
					break;
				}
			}
		}
	}
	out
}

/// Running rows first (the latest started), then the most recently finished, kept in display order.
fn fit(rows: Vec<(Row, bool)>, limit: usize) -> Vec<Row> {
	let mut order: Vec<usize> = (0..rows.len()).collect();
	order.sort_by(|&a, &b| rows[b].1.cmp(&rows[a].1).then(if rows[a].1 { b.cmp(&a) } else { rows[b].0.end.total_cmp(&rows[a].0.end) }));
	let mut keep = vec![false; rows.len()];
	for i in order.into_iter().take(limit) {
		keep[i] = true;
	}
	rows.into_iter().zip(keep).filter(|(_, k)| *k).map(|((r, _), _)| r).collect()
}

fn main() {
	let mut cmd: Vec<String> = std::env::args().skip(1).collect();
	let usage = || -> ! {
		eprintln!("{USAGE}");
		std::process::exit(2)
	};
	let prog = cmd.iter().position(|a| a != "sudo" && !a.starts_with('-')).unwrap_or_else(|| usage());
	if prog > 0 && cmd[0] != "sudo" {
		usage();
	}
	let (mode, extra): (Mode, &[&str]) = match cmd[prog].rsplit('/').next() {
		Some("cargo") => {
			let sub = cmd[prog + 1..].iter().find(|a| !a.starts_with(['+', '-'])).map(String::as_str);
			if !matches!(sub, Some("build" | "check" | "clippy" | "doc")) {
				usage(); // `run` / `test` own the terminal
			}
			let colored = unsafe { libc::isatty(2) } == 1 && !cmd.iter().any(|a| a.starts_with("--color"));
			(Mode::Cargo, if colored { &["--message-format=json-render-diagnostics", "--color=always"] } else { &["--message-format=json-render-diagnostics"] })
		}
		Some("nix" | "nixos-rebuild") => (Mode::Nix, &["--log-format", "internal-json"]),
		_ => usage(),
	};
	let at = cmd.iter().position(|a| a == "--").unwrap_or(cmd.len());
	cmd.splice(at..at, extra.iter().map(|s| s.to_string()));

	let t0 = Instant::now();
	let mut child = Command::new(&cmd[0])
		.args(&cmd[1..])
		.stdout(Stdio::piped())
		.stderr(Stdio::piped())
		.spawn()
		.unwrap_or_else(|e| panic!("spawning {}: {e}", cmd[0]));
	let pid = child.id() as libc::pid_t;
	unsafe { libc::signal(libc::SIGINT, libc::SIG_IGN) }; // ^C reaches the child too; we stay to restore the screen and report
	let live = unsafe { libc::isatty(1) } == 1;
	let log_path = format!("/tmp/build_gantt_{}.log", std::process::id());
	let mut log = BufWriter::new(File::create(&log_path).unwrap_or_else(|e| panic!("{log_path}: {e}")));
	let mut state = State::default();

	let (tx, rx) = mpsc::channel::<(f64, Stream, String)>();
	let pipes: [(Box<dyn Read + Send>, Stream); 2] = [
		(Box::new(child.stdout.take().expect("piped")), Stream::Out),
		(Box::new(child.stderr.take().expect("piped")), Stream::Err),
	];
	std::thread::scope(|s| {
		for (pipe, stream) in pipes {
			let tx = tx.clone();
			s.spawn(move || {
				let _guard = Guard { pid, alt_screen: false };
				let mut reader = BufReader::new(pipe);
				let mut buf = Vec::new();
				while reader.read_until(b'\n', &mut buf).expect("child pipe readable") > 0 {
					let line = String::from_utf8_lossy(&buf).trim_end_matches(['\n', '\r']).to_owned();
					tx.send((t0.elapsed().as_secs_f64(), stream, line)).expect("main loop outlives the readers");
					buf.clear();
				}
			});
		}
		drop(tx);
		let _guard = Guard { pid, alt_screen: live };
		if live {
			print!("\x1b[?1049h\x1b[?25l");
		}
		let mut drawn: Option<Instant> = None;
		loop {
			match rx.recv_timeout(REDRAW) {
				Ok((now, stream, line)) => state.line(mode, stream, &line, now, &mut log),
				Err(RecvTimeoutError::Timeout) => {}
				Err(RecvTimeoutError::Disconnected) => break,
			}
			if live && drawn.is_none_or(|d| d.elapsed() >= REDRAW) {
				let (w, h) = winsize(1).expect("live means stdout is a tty, and ttys have a size");
				let now = t0.elapsed().as_secs_f64();
				let rows = fit(state.rows(now), h.saturating_sub(3).max(1));
				let status: String = state.status.chars().take(w).collect();
				let frame = format!("{}\n{status}\n{}", state.header(now), gantt(&rows, &[], w, now));
				print!("\x1b[H{}\x1b[K\x1b[J", frame.replace('\n', "\x1b[K\n"));
				std::io::stdout().flush().expect("stdout writable");
				drawn = Some(Instant::now());
			}
		}
	});
	let status = child.wait().expect("child was spawned");
	let total = t0.elapsed().as_secs_f64();
	log.flush().expect("log writable");

	let width = winsize(2).or(winsize(1)).map_or(160, |(w, _)| w); // no terminal to fit when both are redirected
	let rows: Vec<Row> = state.rows(total).into_iter().map(|(r, _)| r).collect();
	eprintln!("{}\n{}", state.header(total), gantt(&rows, &[], width, total));
	if rows.iter().any(|r| r.glyph != '█') {
		eprintln!("█ done  ▒ emitted something, still going  ░ started, no artifact yet");
	}
	if mode == Mode::Nix {
		eprintln!("\n{}", state.summary(total));
	}
	if !state.shown.is_empty() {
		eprintln!();
	}
	for (stream, line) in &state.shown {
		match stream {
			Stream::Out => println!("{line}"),
			Stream::Err => eprintln!("{line}"),
		}
	}
	eprintln!("log: {log_path}");
	if !status.success() && !state.hidden.is_empty() {
		eprintln!("log tail:");
		for line in &state.hidden {
			eprintln!("  {line}");
		}
	}
	std::process::exit(status.code().unwrap_or_else(|| 128 + status.signal().expect("no exit code means a signal")));
}
