#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use std::path::Path;
use std::process::Command;

/// Record the tmux/claude working set for `restore_sessions`
#[derive(Parser, Debug)]
#[command(name = "save_sessions")]
struct Args {
    /// Print what would be recorded without writing
    #[arg(short = 'n', long)]
    dry_run: bool,
}

/// `tmux_sessions.tsv`: `session_name\tsession_path` per tmux session; `claude_restore.tsv`: `session_name\tcwd\tsession_id\tconfig_dir\tdraft\trewind` per live tmux-hosted claude, `draft` being its unsubmitted input and `rewind` the prompt it sits rewound to, both with `\\`, `\n`, `\t` escaped.
/// Both consumed by fish's `restore_sessions` on boot.
fn main() {
    let dry_run = Args::parse().dry_run;
    let home = std::env::var("HOME").expect("HOME not set");
    let state_dir = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{home}/.local/state"));
    let sessions_path = format!("{state_dir}/tmux_sessions.tsv");
    let path = format!("{state_dir}/claude_restore.tsv");

    // A boot whose restore never ran through never saw the inventory's sessions, so recording now would erase them.
    let unit = Command::new("systemctl")
        .args(["--user", "show", "-p", "Result", "-p", "ExecMainStartTimestampMonotonic", "claude-session-restore"])
        .output()
        .expect("systemctl unreachable");
    assert!(unit.status.success(), "systemctl --user show failed: {}", String::from_utf8_lossy(&unit.stderr));
    let unit = String::from_utf8_lossy(&unit.stdout);
    let ran = !unit.lines().any(|l| l == "ExecMainStartTimestampMonotonic=0");
    let completed = unit.lines().any(|l| l == "Result=success" || l == "Result=exit-code"); // exit-code: ran to the end, only some entries were stale
    if !(ran && completed) {
        println!("claude-session-restore did not complete this boot ({}); keeping {path} and {sessions_path} untouched", unit.trim().replace('\n', ", "));
        return;
    }

    let (out, sessions) = match (
        Command::new("tmux").args(["list-panes", "-a", "-F", "#{pane_id}\t#{session_name}\t#{pane_width}"]).output(),
        Command::new("tmux").args(["list-sessions", "-F", "#{session_name}\t#{session_path}"]).output(),
    ) {
        (Ok(out), Ok(sessions)) if out.status.success() && sessions.status.success() => (out, String::from_utf8_lossy(&sessions.stdout).into_owned()),
        // No tmux server still records an empty layout, so the previous shutdown cannot linger.
        _ if dry_run => {
            println!("Dry run - no tmux panes; would save an empty inventory to {path} and {sessions_path}");
            return;
        }
        _ => {
            std::fs::write(&sessions_path, "").expect("failed to write empty session inventory");
            std::fs::write(&path, "").expect("failed to write empty claude inventory");
            println!("No tmux panes; saved empty inventory to {path} and {sessions_path}");
            return;
        }
    };
    if dry_run {
        println!("Dry run - would record sessions to {sessions_path}:\n{sessions}");
    } else {
        std::fs::write(&sessions_path, &sessions).expect("failed to write session inventory");
        println!("Recorded {} session(s) to {sessions_path}", sessions.lines().count());
    }
    let panes: Vec<(String, String, usize)> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| {
            let mut f = l.split('\t');
            let mut next = || f.next().expect("format string has three fields").to_string();
            (next(), next(), next().parse().expect("pane_width is a number"))
        })
        .collect();

    // claude keeps `<config_dir>/sessions/<pid>.json` for each live process; `--acc N` sessions live under ~/.claude-accountN
    let mut content = String::new();
    for entry in std::fs::read_dir(&home).expect("HOME unreadable") {
        let config_dir = entry.expect("HOME entry unreadable").path();
        let name = config_dir.file_name().unwrap().to_string_lossy().into_owned();
        if name != ".claude" && !name.starts_with(".claude-account") {
            continue;
        }
        let Ok(sessions) = std::fs::read_dir(config_dir.join("sessions")) else {
            continue; // account never ran an interactive session
        };
        for f in sessions {
            let f = f.expect("sessions entry unreadable").path();
            if f.extension().is_none_or(|e| e != "json") {
                continue;
            }
            let raw = std::fs::read_to_string(&f).expect("session file unreadable");
            let j: serde_json::Value = serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{}: {e}", f.display()));
            let pid = j["pid"].as_u64().unwrap_or_else(|| panic!("{}: no pid", f.display()));
            if !std::path::Path::new(&format!("/proc/{pid}")).exists() {
                continue; // left behind by a crashed claude
            }
            let Some(tmux) = j["tmux"].as_str() else {
                continue; // not launched inside tmux, nothing to rebuild it into
            };
            let pane_id = tmux.rsplit_once('.').unwrap_or_else(|| panic!("{}: unexpected tmux field '{tmux}'", f.display())).1;
            let Some((_, session_name, width)) = panes.iter().find(|(id, ..)| id == pane_id) else {
                continue; // claude on another tmux server
            };
            let cwd = j["cwd"].as_str().unwrap_or_else(|| panic!("{}: no cwd", f.display()));
            let slug: String = cwd.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect(); // how claude names the project dir holding its transcript
            // claude records a physical path, so any symlink in it is a `maintenance mv` redirect left since
            let cwd = match std::fs::canonicalize(cwd) {
                Ok(cwd) => cwd.into_os_string().into_string().expect("cwd is UTF-8"),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => cwd.to_owned(), // deleted: restore reports it stale
                Err(e) => panic!("{cwd}: {e}"),
            };
            let id = j["sessionId"].as_str().unwrap_or_else(|| panic!("{}: no sessionId", f.display()));
            let out = Command::new("tmux").args(["capture-pane", "-p", "-t", pane_id]).output().expect("tmux unreachable");
            assert!(out.status.success(), "capture-pane -t {pane_id} failed: {}", String::from_utf8_lossy(&out.stderr));
            let screen = String::from_utf8_lossy(&out.stdout);
            let rows: Vec<&str> = screen.lines().map(|r| r.trim_end_matches(' ')).collect();
            let (draft, rewind) = match (1..rows.len()).rev().find(|&i| border(rows[i - 1]) && rows[i].starts_with("❯\u{a0}")) {
                Some(top) => {
                    let rewind = rewind(&rows, top, &config_dir.join("projects").join(slug).join(format!("{id}.jsonl"))).unwrap_or_else(|e| {
                        println!("{session_name} ({pane_id}): {e}, so whether it sits rewound is not recorded");
                        None // restores onto the transcript's end, as before rewinds were tracked
                    });
                    let draft = draft(&rows, top, *width).unwrap_or_else(|| {
                        println!("{session_name} ({pane_id}): prompt box runs off screen, its draft is not recorded");
                        String::new() // its bottom border is out of view
                    });
                    (draft, rewind.unwrap_or_default())
                }
                None => {
                    println!("{session_name} ({pane_id}): no prompt box on screen, its draft and rewind are not recorded");
                    (String::new(), String::new()) // a dialog covers the box; nothing to read
                }
            };
            let esc = |s: String| s.replace('\\', "\\\\").replace('\n', "\\n").replace('\t', "\\t");
            content.push_str(&format!("{session_name}\t{cwd}\t{id}\t{}\t{}\t{}\n", config_dir.display(), esc(draft), esc(rewind)));
        }
    }

    let n = content.lines().count();
    if dry_run {
        println!("Dry run - would record {n} claude(s) to {path}:\n{content}");
        return;
    }
    std::fs::write(&path, &content).expect("failed to write claude inventory");
    println!("Recorded {n} claude(s) to {path}");
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

/// Prompt the claude on screen (box at `rows[top]`) sits rewound to; `None` when it shows its transcript's end.
/// A rewind (Esc Esc) lives in claude's memory only until the next send, so it is read off the screen: the last footer (`✻ <verb> for <duration> · done <time>`) renders a `turn_duration` entry, and the screen stops before the prompt after it.
/// shortcut: a turn too short to get a footer leaves a rewind onto it unseen; upgrade if those rewinds matter.
fn rewind(rows: &[&str], top: usize, transcript: &Path) -> Result<Option<String>, String> {
    let shown = &rows[..top - 1];
    if shown.iter().any(|r| r.contains("Jump to bottom")) {
        return Err("its conversation is scrolled up".into());
    }
    let Some(at) = shown.iter().rposition(|r| r.starts_with("✻ ")) else {
        return Ok(None); // no finished turn in view: a long or running last turn
    };
    if shown[at + 1..].iter().any(|r| r.starts_with("❯ ")) {
        return Ok(None); // a prompt went in after that footer
    }
    let Some((_, footer)) = shown[at].split_once(" for ") else {
        return Ok(None); // `✻ Cogitating…`: a turn still running
    };
    let footer = footer.split('│').next().expect("split yields at least one piece"); // the diff panel shares the row
    let mut parts = footer.split(" · ");
    let took = parts.next().expect("split yields at least one piece").trim();
    let done = match parts.find_map(|p| p.trim().strip_prefix("done ")) {
        Some(d) => Some(d.split([' ', ',']).rfind(|w| w.contains(':')).ok_or(format!("its footer's done time '{d}' has no clock"))?.trim_start_matches('0')),
        None => None,
    };

    if !transcript.exists() {
        return Ok(None); // nothing sent yet, nothing to rewind
    }
    let raw = std::fs::read_to_string(transcript).map_err(|e| format!("{}: {e}", transcript.display()))?;
    let entries: Vec<serde_json::Value> = raw
        .lines()
        .map(|l| serde_json::from_str(l).map_err(|e| format!("{}: unparseable line: {e}", transcript.display())))
        .collect::<Result<_, _>>()?;
    let by_uuid: std::collections::HashMap<&str, &serde_json::Value> = entries.iter().filter_map(|e| Some((e["uuid"].as_str()?, e))).collect();
    let mut chain: Vec<&serde_json::Value> = Vec::new(); // what a resume loads: the last entry and its ancestors
    let mut next = entries.iter().rev().find(|e| e["uuid"].is_string());
    while let Some(e) = next {
        chain.push(e);
        next = e["parentUuid"].as_str().and_then(|p| by_uuid.get(p).copied()); // a compaction boundary has none
    }
    chain.reverse();

    let local = |ts: &str| -> [String; 2] {
        let out = Command::new("date").args(["-d", ts, "+%-I:%M %-H:%M"]).output().expect("date unreachable");
        assert!(out.status.success(), "date -d {ts}: {}", String::from_utf8_lossy(&out.stderr));
        let out = String::from_utf8(out.stdout).expect("date prints ASCII");
        let (h12, h24) = out.trim().split_once(' ').expect("format has two fields");
        [h12.to_owned(), h24.to_owned()]
    };
    let turns: Vec<usize> = (0..chain.len())
        .filter(|&i| chain[i]["type"] == "system" && chain[i]["subtype"] == "turn_duration")
        .filter(|&i| chain[i]["durationMs"].as_u64().is_some_and(|ms| duration(ms) == took))
        .filter(|&i| done.is_none_or(|d| chain[i]["timestamp"].as_str().is_some_and(|ts| local(ts).iter().any(|t| t == d))))
        .collect();
    let [turn] = turns[..] else {
        return Err(format!("its last turn footer '{}' matches {} transcript turns", shown[at].trim(), turns.len()));
    };

    let prompts: Vec<String> = chain[turn..].iter().filter_map(|e| prompt(e)).collect();
    let Some(target) = prompts.first() else {
        return Ok(None);
    };
    let norm = |s: &str| s.split_whitespace().collect::<Vec<_>>().join(" ");
    let (t, later) = (norm(target), &prompts[1..]);
    if later.iter().map(|p| norm(p)).any(|p| p.starts_with(&t) || t.starts_with(&p)) {
        return Err(format!("the prompt it sits rewound to repeats later, so the rewind dialog can't tell them apart: '{t}'"));
    }
    Ok(Some(target.clone()))
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
