#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
miette = { version = "7", features = ["fancy"] }
serde_json = "1"
thiserror = "2"
tracing-error = "0.2" # `#[wrap_err]` expands to `::tracing_error::SpanTrace`
v_utils = { version = "2.24", default-features = false, features = ["macros"] }
---
#![feature(error_generic_member_access)]

use clap::Parser;
use std::path::{Path, PathBuf};
use std::process::Command;
use v_utils::macros::wrap_err;

#[wrap_err]
#[derive(Debug, thiserror::Error, miette::Diagnostic)]
enum Error {
    #[leaf]
    #[error("could not run {cmd}")]
    #[diagnostic(code(save_sessions::spawn))]
    Spawn { cmd: String, source: std::io::Error },
    #[leaf]
    #[error("{cmd} failed: {stderr}")]
    #[diagnostic(code(save_sessions::command))]
    Command { cmd: String, stderr: String },
    #[leaf]
    #[error("could not read {}", path.display())]
    #[diagnostic(code(save_sessions::read))]
    Read { path: PathBuf, source: std::io::Error },
    #[leaf]
    #[error("could not write {}", path.display())]
    #[diagnostic(code(save_sessions::write))]
    Write { path: PathBuf, source: std::io::Error },
    #[leaf]
    #[error("{} is not JSON", path.display())]
    #[diagnostic(code(save_sessions::session_file), help("claude rewrites it in place, so one caught mid-write reads torn; rerun"))]
    SessionFile { path: PathBuf, source: serde_json::Error },
}

/// stdout of `cmd`, which has to exit 0
fn run(cmd: &mut Command) -> Result<String, Error> {
    let shown = format!("{cmd:?}");
    let out = cmd.output().map_err(|e| Error::new_spawn(shown.clone(), e))?;
    if !out.status.success() {
        return Err(Error::new_command(shown, String::from_utf8_lossy(&out.stderr).trim().to_owned()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

fn read(path: &Path) -> Result<String, Error> {
    std::fs::read_to_string(path).map_err(|e| Error::new_read(path.to_owned(), e))
}

fn write(path: &str, content: &str) -> Result<(), Error> {
    std::fs::write(path, content).map_err(|e| Error::new_write(path.into(), e))
}

/// `<config_dir>/sessions/*.json`: one per claude process, left behind by crashed ones
fn session_files(config_dir: &Path) -> Result<Vec<(PathBuf, serde_json::Value)>, Error> {
    let dir = config_dir.join("sessions");
    let entries = match std::fs::read_dir(&dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(vec![]), // claude never ran an interactive session
        Err(e) => return Err(Error::new_read(dir, e)),
    };
    let mut files = Vec::new();
    for f in entries {
        let f = f.map_err(|e| Error::new_read(dir.clone(), e))?.path();
        if f.extension().is_none_or(|e| e != "json") {
            continue;
        }
        let j = serde_json::from_str(&read(&f)?).map_err(|e| Error::new_session_file(f.clone(), e))?;
        files.push((f, j));
    }
    Ok(files)
}

/// Record the tmux/claude working set for `restore_sessions`
#[derive(Parser, Debug)]
#[command(name = "save_sessions")]
struct Args {
    /// Print what would be recorded without writing
    #[arg(short = 'n', long)]
    dry_run: bool,
    /// Instead of recording, print how `restore_sessions -r` should pick this claude's turn back up: `continue`, `replay\t<prompt>`, or nothing when it was not cut off
    #[arg(long, value_name = "SESSION_ID")]
    interrupted: Option<String>,
    /// With `--interrupted`: a cut-off turn younger than this, that used only read-only tools, is replayed rather than continued
    #[arg(long, default_value = "45s", value_parser = <v_utils::Timeframe as std::str::FromStr>::from_str)] // clap would pick its panicking `From<&str>`
    replay_within: v_utils::Timeframe,
}

/// `tmux_sessions.tsv`: `session_name\tsession_path` per tmux session; `claude_restore.tsv`: `session_name\tcwd\tsession_id\tdraft\trewind` per live tmux-hosted claude, `draft` being its unsubmitted input and `rewind` the prompt it sits rewound to, both with `\\`, `\n`, `\t` escaped.
/// Both consumed by fish's `restore_sessions` on boot.
fn main() -> miette::Result<()> {
    let args = Args::parse();
    let dry_run = args.dry_run;
    let home = std::env::var("HOME").expect("HOME not set");
    if let Some(id) = args.interrupted {
        match interrupted(&Path::new(&home).join(".claude"), &id, args.replay_within.duration())? {
            Resume::Idle => {}
            Resume::Continue => println!("continue"),
            Resume::Replay(p) => println!("replay\t{}", p.replace('\\', "\\\\").replace('\n', "\\n").replace('\t', "\\t")),
        }
        return Ok(());
    }
    let state_dir = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{home}/.local/state"));
    let sessions_path = format!("{state_dir}/tmux_sessions.tsv");
    let path = format!("{state_dir}/claude_restore.tsv");

    // A boot whose restore never ran through never saw the inventory's sessions, so recording now would erase them.
    let unit = run(Command::new("systemctl").args(["--user", "show", "-p", "Result", "-p", "ExecMainStartTimestampMonotonic", "claude-session-restore"]))?;
    let ran = !unit.lines().any(|l| l == "ExecMainStartTimestampMonotonic=0");
    let completed = unit.lines().any(|l| l == "Result=success" || l == "Result=exit-code"); // exit-code: ran to the end, only some entries were stale
    if !(ran && completed) {
        println!("claude-session-restore did not complete this boot ({}); keeping {path} and {sessions_path} untouched", unit.trim().replace('\n', ", "));
        return Ok(());
    }

    let (out, sessions) = match (
        run(Command::new("tmux").args(["list-panes", "-a", "-F", "#{pane_id}\t#{session_name}\t#{pane_width}\t#{window_index}\t#{pane_index}"])),
        run(Command::new("tmux").args(["list-sessions", "-F", "#{session_name}\t#{session_path}"])),
    ) {
        (Ok(out), Ok(sessions)) => (out, sessions),
        // No tmux server still records an empty layout, so the previous shutdown cannot linger.
        _ if dry_run => {
            println!("Dry run - no tmux panes; would save an empty inventory to {path} and {sessions_path}");
            return Ok(());
        }
        _ => {
            write(&sessions_path, "")?;
            write(&path, "")?;
            println!("No tmux panes; saved empty inventory to {path} and {sessions_path}");
            return Ok(());
        }
    };
    if dry_run {
        println!("Dry run - would record sessions to {sessions_path}:\n{sessions}");
    } else {
        write(&sessions_path, &sessions)?;
        println!("Recorded {} session(s) to {sessions_path}", sessions.lines().count());
    }
    let panes: Vec<(String, String, usize, (usize, usize))> = out
        .lines()
        .map(|l| {
            let mut f = l.split('\t');
            let mut next = || f.next().expect("format string has five fields").to_string();
            let num = |s: String| s.parse::<usize>().unwrap_or_else(|e| panic!("tmux index '{s}': {e}"));
            (next(), next(), num(next()), (num(next()), num(next())))
        })
        .collect();

    let mut entries: Vec<((&str, (usize, usize)), String)> = Vec::new(); // keyed by tmux position: restore appends windows in file order
    let config_dir = Path::new(&home).join(".claude");
    for (f, j) in session_files(&config_dir)? {
        let pid = j["pid"].as_u64().unwrap_or_else(|| panic!("{}: no pid", f.display()));
        if !std::path::Path::new(&format!("/proc/{pid}")).exists() {
            continue; // left behind by a crashed claude
        }
        let Some(tmux) = j["tmux"].as_str() else {
            continue; // not launched inside tmux, nothing to rebuild it into
        };
        let pane_id = tmux.rsplit_once('.').unwrap_or_else(|| panic!("{}: unexpected tmux field '{tmux}'", f.display())).1;
        let Some((_, session_name, width, position)) = panes.iter().find(|(id, ..)| id == pane_id) else {
            continue; // claude on another tmux server
        };
        let cwd = j["cwd"].as_str().unwrap_or_else(|| panic!("{}: no cwd", f.display()));
        let slug: String = cwd.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect(); // how claude names the project dir holding its transcript
        // claude records a physical path, so any symlink in it is a `maintenance mv` redirect left since
        let cwd = match std::fs::canonicalize(cwd) {
            Ok(cwd) => cwd.into_os_string().into_string().expect("cwd is UTF-8"),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => cwd.to_owned(), // deleted: restore reports it stale
            Err(e) => return Err(Error::new_read(cwd.into(), e).into()),
        };
        let id = j["sessionId"].as_str().unwrap_or_else(|| panic!("{}: no sessionId", f.display()));
        let screen = run(Command::new("tmux").args(["capture-pane", "-p", "-t", pane_id]))?;
        let rows: Vec<&str> = screen.lines().map(|r| r.trim_end_matches(' ')).collect();
        let (draft, rewind) = match (1..rows.len()).rev().find(|&i| border(rows[i - 1]) && rows[i].starts_with("❯\u{a0}")) {
            Some(top) => {
                let rewind = match rewind(&rows, top, &config_dir.join("projects").join(slug).join(format!("{id}.jsonl")))? {
                    Rewind::AtEnd => String::new(),
                    Rewind::To(p) => p,
                    Rewind::Unknown(why) => {
                        println!("{session_name} ({pane_id}): {why}, so whether it sits rewound is not recorded");
                        String::new() // restores onto the transcript's end, as before rewinds were tracked
                    }
                };
                let draft = draft(&rows, top, *width).unwrap_or_else(|| {
                    println!("{session_name} ({pane_id}): prompt box runs off screen, its draft is not recorded");
                    String::new() // its bottom border is out of view
                });
                (draft, rewind)
            }
            None => {
                println!("{session_name} ({pane_id}): no prompt box on screen, its draft and rewind are not recorded");
                (String::new(), String::new()) // a dialog covers the box; nothing to read
            }
        };
        let esc = |s: String| s.replace('\\', "\\\\").replace('\n', "\\n").replace('\t', "\\t");
        entries.push(((session_name, *position), format!("{session_name}\t{cwd}\t{id}\t{}\t{}\n", esc(draft), esc(rewind))));
    }
    entries.sort();
    let content: String = entries.into_iter().map(|(_, line)| line).collect();

    let n = content.lines().count();
    if dry_run {
        println!("Dry run - would record {n} claude(s) to {path}:\n{content}");
        return Ok(());
    }
    write(&path, &content)?;
    println!("Recorded {n} claude(s) to {path}");
    Ok(())
}


fn border(r: &str) -> bool {
    r.starts_with('─') && r.ends_with('─') // may carry the session name mid-line
}

/// Unsubmitted input of a claude, read back off its prompt box, whose first row is `rows[top]`; `None` when the box's bottom is off screen.
/// shortcut: a draft taller than the box's on-screen budget keeps only its visible rows, and wide (CJK/emoji) chars skew the wrap widths; upgrade if either bites.
fn draft(rows: &[&str], top: usize, width: usize) -> Option<String> {
    let bottom = top + rows[top..].iter().position(|r| border(r))?;
    let w = width - 4; // what ink wraps the box text at
    let mut text = String::new();
    let mut prev: Option<&str> = None;
    for (i, row) in rows[top..bottom].iter().enumerate() {
        let row = match i {
            0 => row.strip_prefix("❯\u{a0}").expect("matched on it above"),
            _ if row.is_empty() => "",
            _ => row.strip_prefix("  ").unwrap_or_else(|| panic!("prompt box row without its indent: '{row}'")),
        };
        if let Some(p) = prev {
            // ink can't say soft wrap from newline, so infer it: a word that fit on `p` would not have been carried over
            let first = row.split_once(' ').map_or(row, |(f, _)| f).chars().count();
            let last = p.rsplit_once(' ').map_or(p, |(_, l)| l).chars().count();
            let len = p.chars().count();
            text.push_str(match () {
                _ if row.is_empty() => "\n",
                _ if len == w && last + first > w => "", // a word longer than the box, broken mid-word
                _ if len + 1 + first > w => " ",
                _ => "\n",
            });
        }
        text.push_str(row);
        prev = Some(row);
    }
    Some(text)
}

enum Rewind {
    AtEnd,
    To(String),
    Unknown(String),
}

/// Prompt the claude on screen (box at `rows[top]`) sits rewound to.
/// A rewind (Esc Esc) lives in claude's memory only until the next send, so it is read off the screen: the last footer (`✻ <verb> for <duration> · done <time>`) renders a `turn_duration` entry, and the screen stops before the prompt after it.
/// shortcut: a turn too short to get a footer leaves a rewind onto it unseen; upgrade if those rewinds matter.
fn rewind(rows: &[&str], top: usize, transcript: &Path) -> Result<Rewind, Error> {
    let shown = &rows[..top - 1];
    if shown.iter().any(|r| r.contains("Jump to bottom")) {
        return Ok(Rewind::Unknown("its conversation is scrolled up".into()));
    }
    let Some(at) = shown.iter().rposition(|r| r.starts_with("✻ ")) else {
        return Ok(Rewind::AtEnd); // no finished turn in view: a long or running last turn
    };
    if shown[at + 1..].iter().any(|r| r.starts_with("❯ ")) {
        return Ok(Rewind::AtEnd); // a prompt went in after that footer
    }
    let Some((_, footer)) = shown[at].split_once(" for ") else {
        return Ok(Rewind::AtEnd); // `✻ Cogitating…`: a turn still running
    };
    let footer = footer.split('│').next().expect("split yields at least one piece"); // the diff panel shares the row
    let mut parts = footer.split(" · ");
    let took = parts.next().expect("split yields at least one piece").trim();
    let done = match parts.find_map(|p| p.trim().strip_prefix("done ")) {
        Some(d) => match d.split([' ', ',']).rfind(|w| w.contains(':')) {
            Some(clock) => Some(clock.trim_start_matches('0')),
            None => return Ok(Rewind::Unknown(format!("its footer's done time '{d}' has no clock"))),
        },
        None => None,
    };

    if !transcript.exists() {
        return Ok(Rewind::AtEnd); // nothing sent yet, nothing to rewind
    }
    let chain = chain(transcript)?;

    let mut turns = Vec::new();
    for (i, e) in chain.iter().enumerate() {
        if e["type"] != "system" || e["subtype"] != "turn_duration" || e["durationMs"].as_u64().is_none_or(|ms| duration(ms) != took) {
            continue;
        }
        if let Some(d) = done {
            let Some(ts) = e["timestamp"].as_str() else { continue };
            let local = run(Command::new("date").args(["-d", ts, "+%-I:%M %-H:%M"]))?; // the footer shows whichever clock the user runs
            if !local.split_whitespace().any(|t| t == d) {
                continue;
            }
        }
        turns.push(i);
    }
    let [turn] = turns[..] else {
        return Ok(Rewind::Unknown(format!("its last turn footer '{}' matches {} transcript turns", shown[at].trim(), turns.len())));
    };

    let prompts: Vec<String> = chain[turn..].iter().filter_map(|e| prompt(e)).collect();
    let Some(target) = prompts.first() else {
        return Ok(Rewind::AtEnd);
    };
    let norm = |s: &str| s.split_whitespace().collect::<Vec<_>>().join(" ");
    let (t, later) = (norm(target), &prompts[1..]);
    if later.iter().map(|p| norm(p)).any(|p| p.starts_with(&t) || t.starts_with(&p)) {
        return Ok(Rewind::Unknown(format!("the prompt it sits rewound to repeats later, so the rewind dialog can't tell them apart: '{t}'")));
    }
    Ok(Rewind::To(target.clone()))
}

/// What a resume loads: the transcript's last entry and its ancestors, oldest first.
fn chain(transcript: &Path) -> Result<Vec<serde_json::Value>, Error> {
    let raw = read(transcript)?;
    let entries = raw.lines().filter_map(|l| serde_json::from_str::<serde_json::Value>(l).ok()); // claude skips the lines its writers tear (killed mid-line, or two appends interleaved), so a resume never sees them either
    let mut by_uuid: std::collections::HashMap<String, serde_json::Value> = std::collections::HashMap::new();
    let mut last = None;
    for e in entries {
        if let Some(u) = e["uuid"].as_str() {
            last = Some(u.to_owned());
            by_uuid.insert(u.to_owned(), e);
        }
    }
    let mut chain = Vec::new();
    let mut next = last.and_then(|u| by_uuid.remove(&u));
    while let Some(e) = next {
        next = e["parentUuid"].as_str().and_then(|p| by_uuid.remove(p)); // a compaction boundary has none
        chain.push(e);
    }
    chain.reverse();
    Ok(chain)
}

enum Resume {
    Idle,
    Continue,
    Replay(String),
}

/// Whether claude `id`'s last turn was cut off by its process dying, and if so whether that turn did enough to be worth continuing rather than sent again.
/// A live claude is judged on what it wrote before it started, so one already resumed and still sitting on the dead turn counts, while one the user or a resume nudge already moved on does not.
fn interrupted(config_dir: &Path, id: &str, replay_within: std::time::Duration) -> Result<Resume, Error> {
    let projects = config_dir.join("projects");
    let mut transcript = None;
    for d in std::fs::read_dir(&projects).map_err(|e| Error::new_read(projects.clone(), e))? {
        let t = d.map_err(|e| Error::new_read(projects.clone(), e))?.path().join(format!("{id}.jsonl"));
        if t.exists() {
            transcript = Some(t);
            break;
        }
    }
    let Some(transcript) = transcript else {
        return Ok(Resume::Idle); // nothing ever sent
    };
    let mut since: Option<String> = None; // when the live process resuming it started, as a transcript timestamp
    for (f, j) in session_files(config_dir)? {
        let pid = j["pid"].as_u64().unwrap_or_else(|| panic!("{}: no pid", f.display()));
        if j["sessionId"] != id || !Path::new(&format!("/proc/{pid}")).exists() {
            continue;
        }
        if j["status"] != "idle" {
            return Ok(Resume::Idle); // working, so already past the dead turn
        }
        let ms = j["startedAt"].as_u64().unwrap_or_else(|| panic!("{}: no startedAt", f.display()));
        since = Some(run(Command::new("date").args(["-u", "-d", &format!("@{}.{:03}", ms / 1000, ms % 1000), "+%Y-%m-%dT%H:%M:%S.%3NZ"]))?.trim().to_owned()); // a transcript timestamp, which ordered as strings orders in time
    }
    let mut chain = chain(&transcript)?;
    chain.retain(|e| e["message"]["model"] != "<synthetic>"); // what a resume or an API failure writes in the model's place
    let (before, after) = match &since {
        Some(t) => chain.split_at(chain.partition_point(|e| e["timestamp"].as_str().is_none_or(|ts| ts < t.as_str()))), // `Z`-suffixed millis, so they order as strings
        None => (&chain[..], &[][..]),
    };
    if after.iter().any(|e| e["type"] == "assistant" || prompt(e).is_some()) {
        return Ok(Resume::Idle); // this process already took a turn, or has one coming
    }
    let ended = |e: &serde_json::Value| e["type"] == "assistant" && e["message"]["stop_reason"].as_str().is_some_and(|r| r != "tool_use"); // null: cut mid-stream
    let turn = &before[before.iter().rposition(ended).map_or(0, |i| i + 1)..];
    if !turn.iter().any(|e| e["type"] == "assistant" || (e["type"] == "user" && e["isMeta"] != true && e["isCompactSummary"] != true)) {
        let mut pending: Vec<&str> = Vec::new(); // background tasks launched or revived, not yet notified or stopped; a resume notifies the ones the previous process died with
        for e in before {
            let notified = format!("{}{}", e["message"]["content"], e["attachment"]["prompt"]); // a user turn, or an attachment when queued mid-turn
            let stops = e["message"]["content"].as_array().into_iter().flatten().filter(|b| b["type"] == "tool_use" && matches!(b["name"].as_str(), Some("TaskStop" | "KillShell")));
            let stopped: Vec<&str> = stops.flat_map(|b| b["input"].as_object().into_iter().flatten().filter_map(|(_, v)| v.as_str())).collect();
            pending.retain(|t| !notified.contains(&format!("<task-id>{t}</task-id>")) && !stopped.contains(t));
            let r = &e["toolUseResult"];
            pending.extend(r["backgroundTaskId"].as_str().into_iter().chain(r["resumedAgentId"].as_str()).chain((r["status"] == "async_launched").then(|| r["agentId"].as_str()).flatten()));
        }
        return Ok(match pending.is_empty() {
            true => Resume::Idle,
            false => Resume::Continue, // ended its turn to wait on tasks that died with it
        });
    }
    if turn.iter().any(|e| e["type"] == "user" && e["message"]["content"].to_string().contains("[Request interrupted by user")) {
        return Ok(Resume::Idle); // stopped by the user, not by the shutdown
    }
    let prompts: Vec<(usize, String)> = turn.iter().enumerate().filter_map(|(i, e)| Some((i, prompt(e)?))).collect();
    let [(at, p)] = &prompts[..] else {
        return Ok(Resume::Continue); // a task-notification turn, or prompts queued mid-turn that a replay of one would drop
    };
    let tools = turn.iter().filter(|e| e["type"] == "assistant").filter_map(|e| e["message"]["content"].as_array()).flatten().filter(|b| b["type"] == "tool_use");
    // Sending the prompt again redoes the turn, so only one that changed nothing beyond what a rerun would see is replayed.
    let harmless = tools.into_iter().all(|b| matches!(b["name"].as_str(), Some("Read" | "Grep" | "Glob" | "Bash" | "WebFetch" | "WebSearch" | "ToolSearch" | "Skill" | "TaskCreate" | "TaskUpdate" | "TaskList" | "TaskGet" | "ListAgents" | "LSP")));
    let spent = match (turn[*at]["timestamp"].as_str(), turn.iter().rev().find_map(|e| e["timestamp"].as_str())) {
        (Some(from), Some(to)) => secs(to)? - secs(from)?,
        _ => panic!("{}: prompt or last entry lacks a timestamp", transcript.display()),
    };
    // shortcut: wall time stands in for work done, and Bash within `replay_within` is assumed side-effect free; upgrade if a replayed turn ever repeats an effect.
    Ok(match harmless && spent < replay_within.as_secs_f64() {
        true => Resume::Replay(p.clone()),
        false => Resume::Continue,
    })
}

fn secs(iso: &str) -> Result<f64, Error> {
    Ok(run(Command::new("date").args(["-u", "-d", iso, "+%s.%3N"]))?.trim().parse().expect("date printed seconds"))
}

/// Text of a prompt the user typed, as claude's rewind dialog lists them; `None` for tool results, hook/command injections and summaries.
fn prompt(e: &serde_json::Value) -> Option<String> {
    if e["type"] != "user" || e["isMeta"] == true || e["isCompactSummary"] == true || e["isVisibleInTranscriptOnly"] == true {
        return None;
    }
    if e["origin"]["kind"].as_str().is_some_and(|k| k != "human") {
        return None;
    }
    let text = match &e["message"]["content"] {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Array(blocks) if blocks.first().is_some_and(|b| b["type"] != "tool_result") =>
            blocks.iter().filter_map(|b| b["text"].as_str()).collect::<Vec<_>>().join("\n"),
        _ => return None,
    };
    (!text.trim_start().starts_with('<')).then_some(text) // `<command-name>`, `<bash-input>`, `<task-notification>`…
}

/// claude's footer duration, as its `for <duration>` part renders `durationMs`
fn duration(ms: u64) -> String {
    if ms < 60_000 {
        return format!("{}s", ms / 1000);
    }
    let (mut d, mut h, mut m, mut s) = (ms / 86_400_000, ms % 86_400_000 / 3_600_000, ms % 3_600_000 / 60_000, (ms % 60_000 + 500) / 1000);
    if s == 60 {
        (s, m) = (0, m + 1);
    }
    if m == 60 {
        (m, h) = (0, h + 1);
    }
    if h == 24 {
        (h, d) = (0, d + 1);
    }
    match () {
        _ if d > 0 => format!("{d}d {h}h {m}m"),
        _ if h > 0 => format!("{h}h {m}m {s}s"),
        _ if m > 0 => format!("{m}m {s}s"),
        _ => format!("{s}s"),
    }
}
