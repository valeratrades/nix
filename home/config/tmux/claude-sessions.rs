#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
---

use clap::Parser;
use std::collections::{HashMap, HashSet};
use std::process::Command;

#[derive(Parser)]
#[command(about = "Track state of Claude Code processes in tmux windows")]
struct Args {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ClaudeState {
    Empty,    // No claude running (shell prompt)
    Active,   // Claude is processing (spinner visible)
    Finished, // Claude waiting for input (> prompt, no spinner)
}

impl ClaudeState {
    fn as_str(&self) -> &'static str {
        match self {
            ClaudeState::Empty => "empty",
            ClaudeState::Active => "active",
            ClaudeState::Finished => "finished",
        }
    }
}

#[derive(Debug)]
struct ClaudeWindow {
    session: String,
    window_index: u32,
    state: ClaudeState,
}

fn get_claude_windows() -> Vec<ClaudeWindow> {
    let output = Command::new("tmux")
        .args([
            "list-panes",
            "-a",
            "-F",
            "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_current_command}",
        ])
        .output()
        .expect("Failed to execute tmux");

    if !output.status.success() {
        return Vec::new();
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut claude_windows = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.len() < 4 {
            continue;
        }

        let session = parts[0];
        let window_index: u32 = match parts[1].parse() {
            Ok(idx) => idx,
            Err(_) => continue,
        };
        let window_name = parts[2];
        let pane_command = parts[3];

        // Window name must be "claude" or start with "claude"
        if !window_name.eq("claude") && !window_name.starts_with("claude") {
            continue;
        }

        let state = if pane_command == "claude" {
            // Claude is running, check if active or finished
            determine_claude_activity(session, window_index)
        } else {
            ClaudeState::Empty
        };

        claude_windows.push(ClaudeWindow {
            session: session.to_string(),
            window_index,
            state,
        });
    }

    claude_windows
}

fn determine_claude_activity(session: &str, window_index: u32) -> ClaudeState {
    let target = format!("{}:{}", session, window_index);

    let output = Command::new("tmux")
        .args(["capture-pane", "-t", &target, "-p", "-S", "-50"])
        .output();

    let content = match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
        _ => return ClaudeState::Finished, // Default to finished if can't read
    };

    // Check for activity indicators (spinners, "Running...", tool execution)
    // These patterns indicate Claude is actively processing
    let activity_patterns = [
        "Running…",
        "⎿  Running",
        "Thinking…",
        "● Read(",
        "● Bash(",
        "● Edit(",
        "● Write(",
        "● Glob(",
        "● Grep(",
        "● Task(",
        "● WebFetch(",
        "● WebSearch(",
        "● LSP(",
    ];

    // Look at the last portion of the content for activity
    let last_portion: String = content.lines().rev().take(30).collect::<Vec<_>>().join("\n");

    for pattern in activity_patterns {
        if last_portion.contains(pattern) {
            return ClaudeState::Active;
        }
    }

    ClaudeState::Finished
}

fn main() {
    let _args = Args::parse();

    let windows = get_claude_windows();

    // Group windows by session to find sessions with non-empty windows
    let mut session_windows: HashMap<String, Vec<&ClaudeWindow>> = HashMap::new();
    for window in &windows {
        session_windows
            .entry(window.session.clone())
            .or_default()
            .push(window);
    }

    // Find sessions that have at least one non-empty window
    let sessions_with_non_empty: HashSet<String> = session_windows
        .iter()
        .filter(|(_, wins)| wins.iter().any(|w| w.state != ClaudeState::Empty))
        .map(|(session, _)| session.clone())
        .collect();

    // Collect results: show all windows, but skip empty ones if session has non-empty
    // If all windows in a session are empty, show only one empty
    let mut results: Vec<(&str, u32, ClaudeState)> = Vec::new();
    let mut seen_empty_session: HashSet<&str> = HashSet::new();

    for window in &windows {
        if window.state == ClaudeState::Empty {
            if sessions_with_non_empty.contains(&window.session) {
                // Skip empty windows in sessions that have non-empty ones
                continue;
            }
            // For all-empty sessions, only show one empty
            if seen_empty_session.contains(window.session.as_str()) {
                continue;
            }
            seen_empty_session.insert(&window.session);
        }
        results.push((&window.session, window.window_index, window.state));
    }

    // Sort by session name, then window index
    results.sort_by(|a, b| a.0.cmp(b.0).then(a.1.cmp(&b.1)));

    // Output one per line
    for (session, _window_index, state) in results {
        println!("{}: {}", session, state.as_str());
    }
}
