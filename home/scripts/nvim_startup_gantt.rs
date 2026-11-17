#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
libc = "0.2"
regex = "1"
serde_json = "1"
v_utils = { version = "2.25", default-features = false }
---

//! Launches nvim in a pty, then draws a gantt of its startup: --startuptime spans of the embedded server, plus lazy.nvim's
//! profile (plugin loads, configs, event handlers) with real timestamps, until VeryLazy + --settle, so work deferred past
//! the first frame shows too. With --runs > 1 the per-run totals are printed, then the gantt of the fastest run (the least
//! disturbed by load).

#[path = "shared/pty.rs"]
mod pty;
#[path = "shared/winsize.rs"]
mod winsize;

use std::{
	collections::HashMap,
	path::Path,
	process::Command,
	time::{Duration, Instant},
};

use clap::Parser;
use regex::Regex;
use serde_json::Value;
use v_utils::chart::{Marker, Row, gantt};

#[derive(Parser)]
struct Args {
	/// hide spans shorter than this
	#[arg(long, default_value_t = 2.0)]
	min_ms: f64,
	/// ms to keep recording after VeryLazy
	#[arg(long, default_value_t = 300)]
	settle: u64,
	#[arg(long, default_value_t = 1)]
	runs: usize,
	#[arg(long, default_value_t = 15.0)]
	timeout: f64,
	#[arg(trailing_var_arg = true, allow_hyphen_values = true)]
	nvim_args: Vec<String>,
}

// Spans come from wrapping lazy's own profiler (what `:Lazy profile` shows), since LazyLoad fires on vim.schedule.
// --cmd takes one line; the hook's t0 is the `--cmd commands` entry of the log, so both share a clock.
const HOOK: &str = r#"lua
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
"#;

/// Spans (start ms, end ms, label) and marks (name → ms).
type Run = (Vec<(f64, f64, String)>, HashMap<String, f64>);

fn run(args: &Args, dir: &Path) -> Run {
	let (log, out) = (dir.join("startuptime.log"), dir.join("events.json"));
	for p in [&log, &out] {
		if p.exists() {
			std::fs::remove_file(p).unwrap_or_else(|e| panic!("{}: {e}", p.display()));
		}
	}
	let mut cmd = Command::new("nvim");
	cmd.env("NVIM_GANTT_OUT", &out)
		.arg("--startuptime")
		.arg(&log)
		.arg("--cmd")
		.arg(HOOK.replace('\n', " ").replace("SETTLE", &args.settle.to_string()))
		.args(&args.nvim_args);
	let child = pty::Pty::spawn(cmd);
	let started = Instant::now();
	loop {
		if !child.pump(Duration::from_millis(50)) {
			break;
		}
		if started.elapsed().as_secs_f64() >= args.timeout {
			child.kill();
			child.wait();
			eprintln!("nvim did not reach VeryLazy + {}ms within {}s; log: {}", args.settle, args.timeout, log.display());
			std::process::exit(1);
		}
	}
	child.wait();
	parse(&log, &out)
}

fn parse(log: &Path, out: &Path) -> Run {
	let entry = Regex::new(r"^(\d+\.\d+)\s+(\d+\.\d+)(?:\s+(\d+\.\d+))?: (.*)$").unwrap();
	let text = std::fs::read_to_string(log).unwrap_or_else(|e| panic!("{}: {e}", log.display()));
	let mut sections: HashMap<String, Vec<(f64, f64, String)>> = HashMap::new();
	let mut cur: Option<String> = None;
	for l in text.lines() {
		if let Some(rest) = l.strip_prefix("--- Startup times for process:") {
			let name = rest.trim_matches([' ', '-']).to_owned();
			sections.entry(name.clone()).or_default();
			cur = Some(name);
		} else if let (Some(cur), Some(c)) = (&cur, entry.captures(l)) {
			let num = |i: usize| c[i].parse::<f64>().expect("matched digits");
			sections.get_mut(cur).expect("inserted on its header").push((num(1), num(2), c[4].to_owned()));
		}
	}
	// --headless has no UI client
	let server = sections.get("Embedded").or(sections.get("Primary (or UI client)")).expect("startuptime log has a server section");
	let clock_of = |label: &str| server.iter().find(|e| e.2 == label).unwrap_or_else(|| panic!("no `{label}` in {}", log.display())).0;
	let anchor = clock_of("--cmd commands");
	let mut spans: Vec<(f64, f64, String)> = server.iter().map(|(clock, total, label)| (clock - total, *clock, label.clone())).collect();
	let events: Vec<Value> = serde_json::from_str(&std::fs::read_to_string(out).unwrap_or_else(|e| panic!("{}: {e}", out.display()))).expect("the hook writes json");
	let num = |e: &Value, k: &str| e[k].as_f64().unwrap_or_else(|| panic!("event without {k}: {e}"));
	let name = |e: &Value| e["name"].as_str().unwrap_or_else(|| panic!("event without name: {e}")).to_owned();
	let mut marks = HashMap::new();
	for e in &events {
		match e["kind"].as_str() {
			Some("lazy") => spans.push((anchor + num(e, "t") - num(e, "dur"), anchor + num(e, "t"), format!("lazy: {}", name(e)))),
			Some("mark") => {
				marks.insert(name(e), anchor + num(e, "t"));
			}
			_ => panic!("unknown event kind: {e}"),
		}
	}
	marks.insert("NVIM STARTED".to_owned(), clock_of("--- NVIM STARTED ---"));
	(spans, marks)
}

fn main() {
	let args = Args::parse();
	let dir = std::env::temp_dir().join(format!("nvim_gantt_{}", std::process::id()));
	std::fs::create_dir_all(&dir).expect("tmp writable");
	let results: Vec<Run> = (0..args.runs).map(|_| run(&args, &dir)).collect();
	if args.runs > 1 {
		for name in ["NVIM STARTED", "UIEnter", "VeryLazy"] {
			let mut v: Vec<f64> = results.iter().filter_map(|(_, m)| m.get(name).copied()).collect();
			v.sort_by(f64::total_cmp);
			let n = v.len();
			let median = if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 };
			println!("{name:<13} median {median:7.1}ms  min {:7.1}  max {:7.1}", v[0], v[n - 1]);
		}
		println!();
	}
	let (spans, marks) = results.into_iter().min_by(|a, b| a.1["VeryLazy"].total_cmp(&b.1["VeryLazy"])).expect("--runs >= 1");

	let mut spans: Vec<_> = spans.into_iter().filter(|s| s.1 - s.0 >= args.min_ms).collect();
	spans.sort_by(|a, b| a.0.total_cmp(&b.0).then(b.1.total_cmp(&a.1)));
	let runtime = Regex::new(r"/nix/store/[^/]+/share/nvim/runtime").unwrap();
	let home = std::env::var("HOME").expect("HOME set");
	let mut ends: Vec<f64> = Vec::new();
	let rows: Vec<Row> = spans
		.iter()
		.map(|(a, b, label)| {
			ends.retain(|&e| e > a + 1e-3);
			let depth = ends.iter().filter(|&&e| e >= b - 0.05).count(); // lazy spans are end - dur, so containment gets a little slack
			ends.push(*b);
			let label = runtime.replace_all(&label.replace(&home, "~"), "$$VIMRUNTIME").into_owned();
			Row { label, depth, start: a / 1e3, end: b / 1e3, glyph: '█' }
		})
		.collect();
	let glyph = |name: &str| match name {
		"NVIM STARTED" => '┊',
		"UIEnter" => '┆',
		"VeryLazy" => '╎',
		_ => ' ',
	};
	let markers: Vec<Marker> = marks.iter().map(|(name, t)| Marker { at: t / 1e3, glyph: glyph(name), name: name.clone() }).collect();
	let end = rows.iter().map(|r| r.end).chain(markers.iter().map(|m| m.at)).fold(0.0, f64::max);
	let width = winsize::winsize(1).map_or(160, |(w, _)| w); // not a terminal: nothing to fit
	println!("{}", gantt(&rows, &markers, width, end));
	eprintln!("logs: {}", dir.display());
}
