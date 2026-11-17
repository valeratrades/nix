#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
jiff = "0.2"
libc = "0.2"
regex = "1"
v_utils = { version = "2.25", default-features = false }
---

//! Launches an interactive `claude` in a pty, then draws a gantt of its startup from the --debug-file log.
//! Any debug line carrying `in|after|took <N>ms` becomes a span ending at that line; `Starting connection` with no settle
//! line is drawn as pending up to the kill. Runs `claude` from PATH directly, so not under the fish wrapper's slice.

#[path = "shared/pty.rs"]
mod pty;
#[path = "shared/winsize.rs"]
mod winsize;

use std::{
	collections::BTreeSet,
	process::Command,
	time::{Duration, Instant, SystemTime},
};

use clap::Parser;
use regex::Regex;
use v_utils::chart::{Marker, Row, gantt};

#[derive(Parser)]
struct Args {
	/// seconds before giving up on pending MCP servers
	#[arg(long, default_value_t = 40.0)]
	timeout: f64,
	/// hide spans shorter than this
	#[arg(long, default_value_t = 40.0)]
	min_ms: f64,
	#[arg(trailing_var_arg = true, allow_hyphen_values = true)]
	claude_args: Vec<String>,
}

struct Log {
	line: Regex,
	mcp_start: Regex,
	mcp_settle: Regex,
}
impl Log {
	/// (epoch secs, text); continuation lines of multi-line messages carry no timestamp
	fn parse(&self, path: &str) -> Vec<(f64, String)> {
		let Ok(text) = std::fs::read(path) else {
			return Vec::new(); // claude hasn't created it yet
		};
		String::from_utf8_lossy(&text)
			.lines()
			.filter_map(|l| self.line.captures(l))
			.map(|c| {
				let ts: jiff::Timestamp = c[1].parse().unwrap_or_else(|e| panic!("debug log timestamp {}: {e}", &c[1]));
				(ts.as_millisecond() as f64 / 1e3, c[2].to_owned())
			})
			.collect()
	}

	fn pending(&self, lines: &[(f64, String)]) -> BTreeSet<String> {
		let names = |re: &Regex| -> BTreeSet<String> { lines.iter().filter_map(|(_, t)| re.captures(t)).map(|c| c[1].to_owned()).collect() };
		&names(&self.mcp_start) - &names(&self.mcp_settle)
	}
}

fn epoch() -> f64 {
	SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).expect("clock past 1970").as_secs_f64()
}

fn main() {
	let args = Args::parse();
	let dir = std::env::temp_dir().join(format!("cc_gantt_{}", std::process::id()));
	std::fs::create_dir_all(&dir).expect("tmp writable");
	let log_path = dir.join("debug.log").to_str().expect("utf-8 tmp path").to_owned();
	let log = Log {
		line: Regex::new(r"^(\S+Z) \[\w+\] (.*)$").unwrap(),
		mcp_start: Regex::new(r#"MCP server "(.+?)": Starting connection"#).unwrap(),
		mcp_settle: Regex::new(r#"MCP server "(.+?)": .*\b(?:in|after) \d+(?:\.\d+)?ms"#).unwrap(),
	};
	let dur = Regex::new(r"\s*(?:\(.*?\)\s*)?\b(?:in|after|took) (\d+(?:\.\d+)?)ms\b").unwrap();

	let t0 = epoch();
	let started = Instant::now();
	let mut cmd = Command::new("claude");
	cmd.arg("--debug-file").arg(&log_path).args(&args.claude_args);
	let child = pty::Pty::spawn(cmd);
	let mut mounted_at: Option<Instant> = None;
	while started.elapsed().as_secs_f64() < args.timeout && child.pump(Duration::from_millis(200)) {
		let lines = log.parse(&log_path);
		if mounted_at.is_none() && lines.iter().any(|(_, t)| t.contains("REPL mounted")) {
			mounted_at = Some(Instant::now());
		}
		if mounted_at.is_some_and(|m| m.elapsed() > Duration::from_secs(2)) && log.pending(&lines).is_empty() {
			break; // MCP connects only begin after mount
		}
	}
	let t_kill = epoch();
	child.kill();
	child.wait();

	let lines: Vec<(f64, String)> = log.parse(&log_path).into_iter().filter(|(t, _)| *t <= t_kill).collect();
	assert!(!lines.is_empty(), "no debug output in {log_path}");

	let mut spans = vec![(0.0, lines[0].0 - t0, "exec → first log line (binary load + JS init)".to_owned(), '█')];
	for (t, s) in &lines {
		if let Some(c) = dur.captures(s) {
			let d: f64 = c[1].parse::<f64>().expect("matched digits") / 1e3;
			if d * 1e3 >= args.min_ms {
				let m = c.get(0).expect("whole match");
				let label = format!("{}{}", &s[..m.start()], &s[m.end()..]).trim_matches([' ', '.', ':']).to_owned();
				spans.push((t - t0 - d, t - t0, label, '█'));
			}
		}
	}
	let pending = log.pending(&lines);
	for name in &pending {
		let start = lines.iter().find(|(_, s)| log.mcp_start.captures(s).is_some_and(|c| &c[1] == name)).expect("pending means started").0;
		spans.push((start - t0, t_kill - t0, format!("MCP server \"{name}\": PENDING at kill"), '░'));
	}
	spans.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.total_cmp(&b.1)).then(a.2.cmp(&b.2)));
	let mut rows: Vec<Row> = Vec::new();
	for (start, end, label, glyph) in spans {
		if !rows.iter().any(|r| (r.start - start).abs() < 0.05 && (r.end - end).abs() < 0.05) {
			rows.push(Row { label, depth: 0, start, end, glyph }); // one event often logs twice
		}
	}

	let first = |needle: &str| lines.iter().find(|(_, s)| s.contains(needle)).map(|(t, _)| t - t0);
	let mut markers = Vec::new();
	let mount = first("REPL mounted");
	if let Some(at) = mount {
		markers.push(Marker { at, glyph: '┊', name: "prompt usable (REPL mounted)".into() });
	}
	// plugin skills, commands and panels register only after every handler calls next()
	if let Some(at) = rows.iter().filter(|r| r.label.contains("session.start settled")).map(|r| r.end).reduce(f64::max) {
		markers.push(Marker { at, glyph: '┆', name: "session.start chain done".into() });
	}
	let end = rows.iter().map(|r| r.end).fold(0.0, f64::max);
	// a 30s connect timeout would otherwise flatten everything else
	let axis_end = rows.iter().filter(|r| r.end - r.start < 10.0 && r.glyph != '░').map(|r| r.end).fold(0.0, f64::max);
	let width = winsize::winsize(1).map_or(160, |(w, _)| w); // not a terminal: nothing to fit
	println!("{}", gantt(&rows, &markers, width, axis_end));
	if mount.is_some() {
		match pending.len() {
			0 => println!("everything settled at {end:.2}s"),
			n => println!("{n} MCP server(s) still pending at {end:.2}s"),
		}
	}
	eprintln!("log: {log_path}");
}
