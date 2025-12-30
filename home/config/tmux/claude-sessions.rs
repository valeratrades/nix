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
struct Args {
    /// Compact output: hide todos and session summaries
    #[arg(short, long)]
    compact: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TodoItem {
    status: String,
    active_form: String,
}

#[derive(Deserialize)]
struct SessionMessage {
    #[serde(rename = "type")]
    msg_type: String,
    message: Option<MessageContent>,
}

#[derive(Deserialize)]
struct MessageContent {
    role: String,
    content: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ClaudeState {
    Empty,    // No claude running (shell prompt)
    Active,   // Claude is processing (spinner visible)
    Finished, // Claude waiting for input (> prompt, no spinner)
    Draft,    // User is typing a message (bypass permissions prompt visible)
    Error,    // Claude hit an error (rate limit, panic, etc.)
}

impl ClaudeState {
    fn as_str(&self) -> &'static str {
        match self {
            ClaudeState::Empty => "empty",
            ClaudeState::Active => "active",
            ClaudeState::Finished => "finished",
            ClaudeState::Draft => "draft",
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
    summary: Option<String>,
}

#[derive(Debug)]
struct SessionEntry {
    name: String,
    state: ClaudeState,
    active_todo: Option<String>,
    summary: Option<String>,
}

#[derive(Debug)]
struct Sessions {
    entries: Vec<SessionEntry>,
    compact: bool,
}

impl Sessions {
    fn new(compact: bool) -> Self {
        Self {
            entries: Vec::new(),
            compact,
        }
    }

    fn add(&mut self, entry: SessionEntry) {
        self.entries.push(entry);
    }

    fn sort(&mut self) {
        self.entries.sort_by(|a, b| a.name.cmp(&b.name));
    }
}

impl fmt::Display for Sessions {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.entries.is_empty() {
            return Ok(());
        }

        // Calculate max lengths for alignment
        let max_name_len = self
            .entries
            .iter()
            .map(|e| {
                if self.compact {
                    e.name.len()
                } else {
                    // Include summary in length calculation
                    let summary_len = e.summary.as_ref().map(|s| s.len() + 3).unwrap_or(0); // +3 for " <>"
                    e.name.len() + summary_len
                }
            })
            .max()
            .unwrap_or(0);

        let max_state_len = self
            .entries
            .iter()
            .map(|e| e.state.as_str().len())
            .max()
            .unwrap_or(0);

        for (i, entry) in self.entries.iter().enumerate() {
            if i > 0 {
                writeln!(f)?;
            }

            // Build the name with optional summary
            let display_name = if self.compact {
                entry.name.clone()
            } else {
                match &entry.summary {
                    Some(summary) => format!("{} <{}>", entry.name, summary),
                    None => entry.name.clone(),
                }
            };

            // Pad state string manually since colored strings mess up format width
            let state_str = entry.state.as_str();
            let padded_state = format!("{:width$}", state_str, width = max_state_len);

            let colored_state = match entry.state {
                ClaudeState::Active => padded_state.blue(),
                ClaudeState::Finished => padded_state.green(),
                ClaudeState::Empty => padded_state.yellow(),
                ClaudeState::Draft => padded_state.cyan(),
                ClaudeState::Error => padded_state.red(),
            };

            write!(
                f,
                "{:width$}  {}",
                display_name,
                colored_state,
                width = max_name_len
            )?;

            if !self.compact && entry.state == ClaudeState::Active {
                let todo_str = match &entry.active_todo {
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

// Track if ollama failed (for warning message)
static OLLAMA_UNAVAILABLE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Generate a short summary using a local LLM (ollama)
fn generate_summary_with_llm(first_message: &str) -> Option<String> {
    let prompt = format!(
        "Summarize this task in 5 words or less. Reply with ONLY the summary, nothing else:\n\n{}",
        first_message
    );

    let output = match Command::new("ollama")
        .args(["run", "qwen2.5:0.5b", &prompt])
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => {
            OLLAMA_UNAVAILABLE.store(true, std::sync::atomic::Ordering::Relaxed);
            return None;
        }
    };

    let summary = String::from_utf8_lossy(&output.stdout)
        .trim()
        .to_string();

    if summary.is_empty() {
        None
    } else {
        // Limit length just in case
        let max_len = 40;
        if summary.len() > max_len {
            Some(format!("{}...", &summary[..max_len]))
        } else {
            Some(summary)
        }
    }
}

/// Get a short summary from the session's first user message
fn get_session_summary(session_file: &Path) -> Option<String> {
    use std::io::{BufRead, BufReader};

    let file = fs::File::open(session_file).ok()?;
    let reader = BufReader::new(file);

    // Read first few lines to find the first user message
    for line in reader.lines().take(10) {
        let line = line.ok()?;
        if let Ok(msg) = serde_json::from_str::<SessionMessage>(&line) {
            if msg.msg_type == "user" {
                if let Some(content) = msg.message {
                    if content.role == "user" {
                        let first_message = content.content.trim();

                        // Try to generate summary with LLM
                        if let Some(summary) = generate_summary_with_llm(first_message) {
                            return Some(summary);
                        }

                        // Fallback: use truncated first line of message
                        let summary = first_message
                            .lines()
                            .next()
                            .unwrap_or(first_message);

                        let max_len = 50;
                        if summary.len() > max_len {
                            return Some(format!("{}...", &summary[..max_len]));
                        }
                        return Some(summary.to_string());
                    }
                }
            }
        }
    }

    None
}

/// Find the most recent session file path for a project
fn find_active_session_file(project_dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(project_dir).ok()?;

    let mut session_files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            name_str.ends_with(".jsonl") && !name_str.starts_with("agent-")
        })
        .filter_map(|e| {
            let metadata = e.metadata().ok()?;
            let modified = metadata.modified().ok()?;
            Some((e.path(), modified))
        })
        .collect();

    session_files.sort_by(|a, b| b.1.cmp(&a.1));
    session_files.first().map(|(path, _)| path.clone())
}

/// Get session info (todo and summary) for a tmux pane
fn get_session_info_for_pane(shell_pid: u32) -> (Option<String>, Option<String>) {
    let info = (|| -> Option<(Option<String>, Option<String>)> {
        let claude_pid = get_child_pid(shell_pid)?;
        let cwd = get_process_cwd(claude_pid)?;
        let project_name = path_to_project_name(&cwd);

        let home = std::env::var("HOME").ok()?;
        let project_dir = PathBuf::from(&home)
            .join(".claude/projects")
            .join(&project_name);

        let session_file = find_active_session_file(&project_dir)?;
        let session_id = session_file
            .file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.to_string())?;

        let todo = get_active_todo_from_session(&session_id);
        let summary = get_session_summary(&session_file);

        Some((todo, summary))
    })();

    info.unwrap_or((None, None))
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

        let (state, active_todo, summary) = if pane_command == "claude" {
            // Claude is running, check if active or finished
            let state = determine_claude_activity(session, window_index);
            let (active_todo, summary) = if state == ClaudeState::Active {
                get_session_info_for_pane(pane_pid)
            } else {
                // Still get summary for non-active states
                let (_, summary) = get_session_info_for_pane(pane_pid);
                (None, summary)
            };
            (state, active_todo, summary)
        } else {
            (ClaudeState::Empty, None, None)
        };

        claude_windows.push(ClaudeWindow {
            session: session.to_string(),
            window_index,
            state,
            active_todo,
            summary,
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

    // Look at the last few lines for various indicators
    let last_portion: String = content.lines().rev().take(15).collect::<Vec<_>>().join("\n");

    // Match spinner pattern first: "Word…" (capitalized word followed by ellipsis)
    // Examples: Running…, Thinking…, Cogitating…, Summarizing…
    // This takes priority because spinners indicate active processing
    let spinner_pattern = Regex::new(r"[A-Z][a-z]+…").unwrap();

    if spinner_pattern.is_match(&last_portion) {
        return ClaudeState::Active;
    }

    // Check for draft state: user has typed something after "> "
    // The bypass permissions prompt is visible and there's actual text after "> "
    if last_portion.contains("bypass permissions") {
        // Find the line starting with "> " and check if there's text after it
        for line in content.lines() {
            if line.starts_with("> ") {
                let after_prompt = line[2..].trim();
                if !after_prompt.is_empty() {
                    return ClaudeState::Draft;
                }
            }
        }
    }

    // If the last line starts with "> " (input prompt), Claude is waiting for input
    if last_line.starts_with("> ") {
        return ClaudeState::Finished;
    }

    // Check for error patterns (rate limit, panics, errors)
    let error_pattern = Regex::new(r"(?i)(rate.?limit|error:|panicked|PANIC|timed.?out)").unwrap();

    if error_pattern.is_match(&last_portion) {
        return ClaudeState::Error;
    }

    ClaudeState::Finished
}

fn main() {
    let args = Args::parse();

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
    let mut results: Vec<&ClaudeWindow> = Vec::new();
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
        results.push(window);
    }

    // Sort by session name, then window index
    results.sort_by(|a, b| a.session.cmp(&b.session).then(a.window_index.cmp(&b.window_index)));

    // Build Sessions struct
    let mut sessions = Sessions::new(args.compact);
    for window in results {
        sessions.add(SessionEntry {
            name: window.session.clone(),
            state: window.state,
            active_todo: window.active_todo.clone(),
            summary: window.summary.clone(),
        });
    }
    sessions.sort();

    // Show warning if ollama was unavailable (only in non-compact mode with summaries)
    if !args.compact && OLLAMA_UNAVAILABLE.load(std::sync::atomic::Ordering::Relaxed) {
        eprintln!("{}", "warn: ollama unavailable, using fallback summaries".yellow());
    }

    println!("{}", sessions);
}
