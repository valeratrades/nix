#!/home/v/nix/home/scripts/nix-run-cached
---cargo

[package]
edition = "2024"

[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
serde_json = "1"
---

use clap::Parser;
use std::process::Command;

/// Record the tmux/claude working set for `restore_sessions`
#[derive(Parser, Debug)]
#[command(name = "save_sessions")]
struct Args {
    /// Print what would be recorded without writing
    #[arg(short = 'n', long)]
    dry_run: bool,
}

/// `tmux_sessions.tsv`: `session_name\tsession_path` per tmux session; `claude_restore.tsv`: `session_name\tcwd\tsession_id\tconfig_dir\tdraft` per live tmux-hosted claude, `draft` being its unsubmitted input with `\\`, `\n`, `\t` escaped.
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
            // claude records a physical path, so any symlink in it is a `maintenance mv` redirect left since
            let cwd = match std::fs::canonicalize(cwd) {
                Ok(cwd) => cwd.into_os_string().into_string().expect("cwd is UTF-8"),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => cwd.to_owned(), // deleted: restore reports it stale
                Err(e) => panic!("{cwd}: {e}"),
            };
            let id = j["sessionId"].as_str().unwrap_or_else(|| panic!("{}: no sessionId", f.display()));
            let draft = draft(pane_id, *width).unwrap_or_else(|| {
                println!("{session_name} ({pane_id}): no prompt box on screen, its draft is not recorded");
                String::new() // a dialog covers the box; nothing to read
            });
            let draft = draft.replace('\\', "\\\\").replace('\n', "\\n").replace('\t', "\\t");
            content.push_str(&format!("{session_name}\t{cwd}\t{id}\t{}\t{draft}\n", config_dir.display()));
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


/// Unsubmitted input of the claude in `pane`, read back off its prompt box; `None` when no box is on screen.
/// shortcut: a draft taller than the box's on-screen budget keeps only its visible rows, and wide (CJK/emoji) chars skew the wrap widths; upgrade if either bites.
fn draft(pane: &str, width: usize) -> Option<String> {
    let out = Command::new("tmux").args(["capture-pane", "-p", "-t", pane]).output().expect("tmux unreachable");
    assert!(out.status.success(), "capture-pane -t {pane} failed: {}", String::from_utf8_lossy(&out.stderr));
    let screen = String::from_utf8_lossy(&out.stdout);
    let rows: Vec<&str> = screen.lines().map(|r| r.trim_end_matches(' ')).collect();
    let border = |r: &str| r.starts_with('─') && r.ends_with('─'); // may carry the session name mid-line
    let top = (1..rows.len()).rev().find(|&i| border(rows[i - 1]) && rows[i].starts_with("❯\u{a0}"))?;
    let bottom = top + rows[top..].iter().position(|r| border(r))?;
    let w = width - 4; // what ink wraps the box text at
    let mut text = String::new();
    let mut prev: Option<&str> = None;
    for (i, row) in rows[top..bottom].iter().enumerate() {
        let row = match i {
            0 => row.strip_prefix("❯\u{a0}").expect("matched on it above"),
            _ if row.is_empty() => "",
            _ => row.strip_prefix("  ").unwrap_or_else(|| panic!("{pane}: prompt box row without its indent: '{row}'")),
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
