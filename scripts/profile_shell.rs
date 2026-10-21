#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
regex = "1"
---

//! Shell latency profiler: fish startup, starship prompt, direnv export. See github.com/valeratrades/nix/issues/22.
//! Runs from (and measures) the current dir; first-prompt cost depends on it.

use std::{
	collections::HashMap,
	process::{Command, Stdio},
	time::Instant,
};

use clap::{Parser, ValueEnum};
use regex::Regex;

#[derive(Parser)]
struct Args {
	#[arg(value_enum, default_value = "all")]
	what: What,
	#[arg(short, long, default_value_t = 10)]
	runs: usize,
	/// hide fish profile entries below this many ms
	#[arg(short, long, default_value_t = 2.0)]
	threshold: f64,
	#[arg(short, long, default_value_t = 8)]
	depth: usize,
	/// also strace one run, showing every spawned process on a timeline
	#[arg(short, long)]
	spawns: bool,
	/// measure as-is, competing with whatever else runs in our cgroup. Default re-execs into a CPUWeight=1000 scope, so numbers stay comparable across load
	#[arg(short, long)]
	contended: bool,
	#[arg(long, hide = true)]
	in_scope: bool,
}

#[derive(Clone, Copy, PartialEq, ValueEnum)]
enum What {
	All,
	Startup,
	Prompt,
	Direnv,
}

const DIRENV_STATE: [&str; 4] = ["DIRENV_DIR", "DIRENV_FILE", "DIRENV_DIFF", "DIRENV_WATCHES"];

fn main() {
	let args = Args::parse();
	if !args.contended && !args.in_scope {
		let status = Command::new("systemd-run")
			.args(["--user", "--scope", "--quiet", "-p", "CPUWeight=1000", "--"])
			.args(std::env::args())
			.arg("--in-scope")
			.status()
			.expect("systemd-run is on every host");
		std::process::exit(status.code().expect("not killed by a signal"));
	}

	let all = args.what == What::All;
	if all || args.what == What::Startup {
		startup(&args);
	}
	if all || args.what == What::Prompt {
		prompt(&args);
	}
	if all || args.what == What::Direnv {
		direnv(&args);
	}
}

fn startup(args: &Args) {
	header("fish startup");
	wall("fish -i -c exit", args.runs, || Command::new("fish").args(["-i", "-c", "exit"]).status());
	wall("fish --no-config -i -c exit (floor)", args.runs, || Command::new("fish").args(["--no-config", "-i", "-c", "exit"]).status());

	let line_re = Regex::new(r"^\s*(\d+)\s+(\d+)\s+(-+>)\s?(.*)$").unwrap();
	let prof = std::env::temp_dir().join(format!("profile_shell.{}.prof", std::process::id()));
	// key: (depth, text, nth occurrence of that pair) -> per-run (start_us, total_us)
	let mut entries: HashMap<(usize, String, usize), Vec<(f64, f64)>> = HashMap::new();
	let mut order: Vec<(usize, String, usize)> = Vec::new();
	for _ in 0..args.runs {
		let status = Command::new("fish")
			.arg(format!("--profile-startup={}", prof.display()))
			.args(["-i", "-c", "exit"])
			.stdout(Stdio::null())
			.status()
			.unwrap();
		assert!(status.success());
		let text = std::fs::read_to_string(&prof).unwrap();
		let mut next_start: Vec<f64> = vec![0.0; 64];
		let mut seen: HashMap<(usize, String), usize> = HashMap::new();
		for line in text.lines().skip(1) {
			let Some(c) = line_re.captures(line) else { continue }; // continuation lines of multi-line commands
			let total: f64 = c[2].parse().unwrap();
			let depth = c[3].len();
			let cmd = c[4].chars().take(100).collect::<String>();
			let start = next_start[depth];
			next_start[depth] = start + total;
			next_start[depth + 1] = start;
			let n = seen.entry((depth, cmd.clone())).or_insert(0);
			let key = (depth, cmd, *n);
			*n += 1;
			if !entries.contains_key(&key) {
				order.push(key.clone());
			}
			entries.entry(key).or_default().push((start, total));
		}
	}
	std::fs::remove_file(&prof).unwrap();

	let rows: Vec<_> = order
		.iter()
		.filter(|k| k.0 <= args.depth)
		.map(|k| {
			let v = &entries[k];
			let start = median(v.iter().map(|e| e.0).collect()) / 1000.0;
			// absent in some runs counts as 0, so a rarely-hit branch doesn't look like it's always paid
			let mut totals: Vec<f64> = v.iter().map(|e| e.1).collect();
			totals.resize(args.runs, 0.0);
			(k, start, median(totals) / 1000.0)
		})
		.filter(|r| r.2 >= args.threshold)
		.collect();
	let end = rows.iter().map(|r| r.1 + r.2).fold(0.0, f64::max);
	println!("\n  profile (median of {} runs, ms; nested lines are included in their parent):", args.runs);
	for (k, start, total) in rows {
		println!(
			"  {:>6.1} {:>6.1}  {}  {}{}",
			start,
			total,
			bar(start, total, end, 40),
			"  ".repeat(k.0 - 1),
			k.1
		);
	}
	if args.spawns {
		spawns(Command::new("fish").args(["-i", "-c", "exit"]));
	}
}

fn prompt(args: &Args) {
	header("starship prompt");
	let ansi = Regex::new(r"\x1b\[[0-9;]*m").unwrap();
	let row = Regex::new(r"^\s*(\S+)\s+-\s+(<?)(\d+)ms").unwrap();
	let mut modules: HashMap<String, Vec<f64>> = HashMap::new();
	for _ in 0..args.runs {
		let out = Command::new("starship").arg("timings").output().unwrap();
		assert!(out.status.success());
		for line in String::from_utf8(out.stdout).unwrap().lines() {
			let line = ansi.replace_all(line, "");
			let Some(c) = row.captures(&line) else { continue }; // header and the breakdown section
			let ms: f64 = if c[2].is_empty() { c[3].parse().unwrap() } else { 0.5 };
			modules.entry(c[1].to_string()).or_default().push(ms);
		}
	}
	let mut sorted: Vec<_> = modules.into_iter().collect();
	sorted.sort_by(|a, b| max(&b.1).total_cmp(&max(&a.1)));
	println!("  modules run in parallel; latency ~ slowest module. starship lists only >=1ms or non-empty ones:");
	println!("  {:<20} {:>6} {:>6}  {}", "module", "p50", "max", "shown");
	for (name, v) in sorted {
		println!("  {:<20} {:>6.1} {:>6.1}  {}/{}", name, median(v.clone()), max(&v), v.len(), args.runs);
	}
	wall("starship prompt", args.runs, || Command::new("starship").args(["prompt", "--terminal-width=200"]).stdout(Stdio::null()).status());
	wall("starship prompt --right", args.runs, || {
		Command::new("starship").args(["prompt", "--right", "--terminal-width=200"]).stdout(Stdio::null()).status()
	});
	if args.spawns {
		spawns(Command::new("starship").args(["prompt", "--right", "--terminal-width=200"]).stdout(Stdio::null()));
	}
}

fn direnv(args: &Args) {
	header("direnv export (fresh shell: no inherited DIRENV_* state)");
	let cmd = || {
		let mut c = Command::new("direnv");
		c.args(["export", "fish"]).stdout(Stdio::null()).stderr(Stdio::null());
		for v in DIRENV_STATE {
			c.env_remove(v);
		}
		c
	};
	wall("direnv export fish", args.runs, || cmd().status());
	if args.spawns {
		spawns(&mut cmd());
	}
}

/// Prints p50/p90/max wall time of `runs` executions.
fn wall(name: &str, runs: usize, mut f: impl FnMut() -> std::io::Result<std::process::ExitStatus>) {
	let mut ms: Vec<f64> = (0..runs)
		.map(|_| {
			let t = Instant::now();
			let status = f().unwrap();
			assert!(status.success(), "{name} failed: {status}");
			t.elapsed().as_secs_f64() * 1000.0
		})
		.collect();
	ms.sort_by(f64::total_cmp);
	let p90 = ms[(ms.len() * 9 / 10).min(ms.len() - 1)];
	println!("  {:<40} p50 {:>7.1}ms  p90 {:>7.1}ms  max {:>7.1}ms", name, median(ms.clone()), p90, ms[ms.len() - 1]);
}

/// One strace'd run of `cmd`; every exec'd process on a timeline.
fn spawns(cmd: &mut Command) {
	let log = std::env::temp_dir().join(format!("profile_shell.{}.strace", std::process::id()));
	let mut strace = Command::new("strace");
	strace.args(["-f", "-q", "-s", "200", "-ttt", "-e", "trace=execve", "-e", "signal=none", "-o"]).arg(&log).arg(cmd.get_program()).args(cmd.get_args());
	for (k, v) in cmd.get_envs() {
		match v {
			Some(v) => strace.env(k, v),
			None => strace.env_remove(k),
		};
	}
	let status = strace.stdout(Stdio::null()).stderr(Stdio::null()).status().expect("strace is installed");
	assert!(status.success());
	let text = std::fs::read_to_string(&log).unwrap();
	std::fs::remove_file(&log).unwrap();

	let exec = Regex::new(r#"^(\d+)\s+([\d.]+) execve\("[^"]*", \[(.*?)\]"#).unwrap();
	let exit = Regex::new(r"^(\d+)\s+([\d.]+) \+\+\+ exited").unwrap();
	let mut procs: Vec<(u32, f64, Option<f64>, String)> = Vec::new();
	for line in text.lines() {
		if let Some(c) = exec.captures(line).filter(|_| !line.contains("= -1")) {
			let pid = c[1].parse().unwrap();
			let argv = c[3].replace('"', "").replace(", ", " ");
			match procs.iter_mut().find(|p| p.0 == pid) {
				Some(p) => p.3 = argv, // exec after exec (wrappers): keep the last image
				None => procs.push((pid, c[2].parse().unwrap(), None, argv)),
			}
		} else if let Some(c) = exit.captures(line) {
			let pid: u32 = c[1].parse().unwrap();
			if let Some(p) = procs.iter_mut().find(|p| p.0 == pid) {
				p.2 = Some(c[2].parse().unwrap());
			}
		}
	}
	let t0 = procs.first().expect("traced at least the command itself").1;
	let end = procs.iter().filter_map(|p| p.2).fold(t0, f64::max);
	println!("\n  spawns ({} processes; ms from start):", procs.len());
	for (_, s, e, argv) in &procs {
		let (s, d) = ((s - t0) * 1000.0, (e.unwrap_or(end) - s) * 1000.0);
		println!("  {:>7.1} {:>7.1}  {}  {}", s, d, bar(s, d, (end - t0) * 1000.0, 40), argv.chars().take(110).collect::<String>());
	}
}

fn header(s: &str) {
	println!("\n== {s} ==");
}

fn bar(start: f64, len: f64, end: f64, width: usize) -> String {
	let scale = width as f64 / end.max(f64::MIN_POSITIVE);
	let a = ((start * scale) as usize).min(width);
	let b = (((start + len) * scale).ceil() as usize).clamp(a + 1, width.max(a + 1));
	format!("{}{}{}", " ".repeat(a), "█".repeat(b - a), " ".repeat(width.saturating_sub(b)))
}

fn median(mut v: Vec<f64>) -> f64 {
	v.sort_by(f64::total_cmp);
	v[v.len() / 2]
}

fn max(v: &[f64]) -> f64 {
	v.iter().copied().fold(f64::MIN, f64::max)
}
