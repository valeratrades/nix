#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
colored = "2"
regex = "1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
---

use clap::Parser;
use colored::Colorize;
use regex::Regex;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Parser)]
#[command(about = "Track state of Claude Code processes in tmux windows")]
struct Args {}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TodoItem {
    status: String,
    active_form: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ClaudeState {
    Empty,    // No claude running (shell prompt)
    Active,   // Claude is processing (spinner visible)
    Finished, // Claude waiting for input (> prompt, no spinner)
    Error,    // Claude hit an error (rate limit, panic, etc.)
}

impl ClaudeState {
    fn as_str(&self) -> &'static str {
        match self {
            ClaudeState::Empty => "empty",
            ClaudeState::Active => "active",
            ClaudeState::Finished => "finished",
            ClaudeState::Error => "error",
        }
    }
}

#[derive(Debug)]
struct ClaudeWindow {
    session: String,
    window_index: u32,
    state: ClaudeState,
    active_todo: Option<String>,
}

#[derive(Debug)]
struct Sessions {
    entries: Vec<(String, ClaudeState, Option<String>)>,
}

impl Sessions {
    fn new() -> Self {
        Self { entries: Vec::new() }
    }

    fn add(&mut self, session: String, state: ClaudeState, active_todo: Option<String>) {
        self.entries.push((session, state, active_todo));
    }

    fn sort(&mut self) {
        self.entries.sort_by(|a, b| a.0.cmp(&b.0));
    }
}

impl fmt::Display for Sessions {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.entries.is_empty() {
            return Ok(());
        }

        let max_session_len = self.entries.iter().map(|(s, _, _)| s.len()).max().unwrap_or(0);
        let max_state_len = self
            .entries
            .iter()
            .map(|(_, state, _)| state.as_str().len())
            .max()
            .unwrap_or(0);

        for (i, (session, state, active_todo)) in self.entries.iter().enumerate() {
            if i > 0 {
                writeln!(f)?;
            }

            // Pad state string manually since colored strings mess up format width
            let state_str = state.as_str();
            let padded_state = format!("{:width$}", state_str, width = max_state_len);

            let colored_state = match state {
                ClaudeState::Active => padded_state.blue(),
                ClaudeState::Finished => padded_state.green(),
                ClaudeState::Empty => padded_state.yellow(),
                ClaudeState::Error => padded_state.red(),
            };

            write!(f, "{:swidth$}  {}", session, colored_state, swidth = max_session_len)?;

            if *state == ClaudeState::Active {
                let todo_str = match active_todo {
                    Some(todo) => format!("[{}]", todo),
                    None => "[]".to_string(),
                };
                write!(f, "  {}", todo_str)?;
            }
        }
        Ok(())
    }
}

/// Get the child process PID of a shell (the claude process)
fn get_child_pid(shell_pid: u32) -> Option<u32> {
    let output = Command::new("pgrep")
        .args(["-P", &shell_pid.to_string()])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .next()
        .and_then(|s| s.parse().ok())
}

/// Get the CWD of a process from /proc
fn get_process_cwd(pid: u32) -> Option<PathBuf> {
    fs::read_link(format!("/proc/{}/cwd", pid)).ok()
}

/// Convert a path to Claude's project path format
/// e.g., /home/v/s/todo -> -home-v-s-todo
fn path_to_project_name(path: &Path) -> String {
    path.to_string_lossy().replace('/', "-")
}

/// Find the most recently modified session file for a project
fn find_active_session_id(project_dir: &Path) -> Option<String> {
    let entries = fs::read_dir(project_dir).ok()?;

    let mut session_files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            // Only consider main session files (UUID.jsonl), not agent files
            name_str.ends_with(".jsonl") && !name_str.starts_with("agent-")
        })
        .filter_map(|e| {
            let metadata = e.metadata().ok()?;
            let modified = metadata.modified().ok()?;
            Some((e.path(), modified))
        })
        .collect();

    // Sort by modification time, most recent first
    session_files.sort_by(|a, b| b.1.cmp(&a.1));

    // Get the session ID from the most recent file
    session_files.first().and_then(|(path, _)| {
        path.file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.to_string())
    })
}

/// Find todo files matching a session ID and get the active (in_progress) todo
fn get_active_todo_from_session(session_id: &str) -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let todos_dir = PathBuf::from(home).join(".claude/todos");

    let entries = fs::read_dir(&todos_dir).ok()?;

    // Find todo files that start with this session ID
    let mut todo_files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            name_str.starts_with(session_id) && name_str.ends_with(".json")
        })
        .filter_map(|e| {
            let metadata = e.metadata().ok()?;
            let modified = metadata.modified().ok()?;
            Some((e.path(), modified))
        })
        .collect();

    // Sort by modification time, most recent first
    todo_files.sort_by(|a, b| b.1.cmp(&a.1));

    // Try each todo file until we find an in_progress item
    for (path, _) in todo_files {
        if let Some(todo) = read_active_todo(&path) {
            return Some(todo);
        }
    }

    None
}

/// Read a todo file and return the first in_progress item's activeForm
fn read_active_todo(path: &Path) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    let todos: Vec<TodoItem> = serde_json::from_str(&content).ok()?;

    todos
        .iter()
        .find(|t| t.status == "in_progress")
        .map(|t| t.active_form.clone())
}

/// Main function to get active todo for a tmux pane
fn get_active_todo_for_pane(shell_pid: u32) -> Option<String> {
    // Get the claude process (child of shell)
    let claude_pid = get_child_pid(shell_pid)?;

    // Get the CWD of the claude process
    let cwd = get_process_cwd(claude_pid)?;

    // Convert to project name
    let project_name = path_to_project_name(&cwd);

    // Build path to project directory
    let home = std::env::var("HOME").ok()?;
    let project_dir = PathBuf::from(home)
        .join(".claude/projects")
        .join(&project_name);

    // Find the active session ID
    let session_id = find_active_session_id(&project_dir)?;

    // Get the active todo for this session
    get_active_todo_from_session(&session_id)
}

fn get_claude_windows() -> Vec<ClaudeWindow> {
    let output = Command::new("tmux")
        .args([
            "list-panes",
            "-a",
            "-F",
            "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_current_command}\t#{pane_pid}",
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
        if parts.len() < 5 {
            continue;
        }

        let session = parts[0];
        let window_index: u32 = match parts[1].parse() {
            Ok(idx) => idx,
            Err(_) => continue,
        };
        let window_name = parts[2];
        let pane_command = parts[3];
        let pane_pid: u32 = match parts[4].parse() {
            Ok(pid) => pid,
            Err(_) => continue,
        };

        // Window name must be "claude" or start with "claude"
        if !window_name.eq("claude") && !window_name.starts_with("claude") {
            continue;
        }

        let (state, active_todo) = if pane_command == "claude" {
            // Claude is running, check if active or finished
            let state = determine_claude_activity(session, window_index);
            let active_todo = if state == ClaudeState::Active {
                get_active_todo_for_pane(pane_pid)
            } else {
                None
            };
            (state, active_todo)
        } else {
            (ClaudeState::Empty, None)
        };

        claude_windows.push(ClaudeWindow {
            session: session.to_string(),
            window_index,
            state,
            active_todo,
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

    // Find the last non-empty line
    let last_line = content
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .unwrap_or("");

    // If the last line starts with "> " (input prompt), Claude is waiting for input
    if last_line.starts_with("> ") {
        return ClaudeState::Finished;
    }

    // Look at the last few lines for various indicators
    let last_portion: String = content.lines().rev().take(15).collect::<Vec<_>>().join("\n");

    // Check for error patterns (rate limit, panics, errors)
    let error_patterns = [
        "rate limit",
        "Rate limit",
        "error:",
        "Error:",
        "panicked",
        "PANIC",
        "failed",
        "Failed",
        "timed out",
        "Timed out",
    ];

    for pattern in error_patterns {
        if last_portion.contains(pattern) {
            return ClaudeState::Error;
        }
    }

    // Match spinner pattern: "Word…" (capitalized word followed by ellipsis)
    // Examples: Running…, Thinking…, Cogitating…, Summarizing…
    let spinner_pattern = Regex::new(r"[A-Z][a-z]+…").unwrap();

    if spinner_pattern.is_match(&last_portion) {
        return ClaudeState::Active;
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
    let mut results: Vec<(&str, u32, ClaudeState, Option<String>)> = Vec::new();
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
        results.push((
            &window.session,
            window.window_index,
            window.state,
            window.active_todo.clone(),
        ));
    }

    // Sort by session name, then window index
    results.sort_by(|a, b| a.0.cmp(b.0).then(a.1.cmp(&b.1)));

    // Build Sessions struct
    let mut sessions = Sessions::new();
    for (session, _, state, active_todo) in results {
        sessions.add(session.to_string(), state, active_todo);
    }
    sessions.sort();

    println!("{}", sessions);
}
