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
use serde::{Deserialize, Serialize};
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

    /// JSON output for eww integration
    #[arg(short, long)]
    json: bool,

    /// Generate LLM summaries (slow, uses ollama)
    #[arg(long)]
    llm_summaries: bool,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
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
    draft_content: Option<String>,
    summary: Option<String>,
}

#[derive(Debug, Serialize)]
struct SessionEntry {
    name: String,
    window_index: u32,
    state: ClaudeState,
    active_todo: Option<String>,
    draft_content: Option<String>,
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
                // In non-compact mode, name includes ":window_index"
                let base_name_len = if self.compact {
                    e.name.len()
                } else {
                    e.name.len() + 1 + e.window_index.to_string().len() // +1 for ":"
                };
                if self.compact {
                    base_name_len
                } else {
                    // Include summary in length calculation
                    let summary_len = e.summary.as_ref().map(|s| s.len() + 3).unwrap_or(0); // +3 for " <>"
                    base_name_len + summary_len
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

            // Build the name with window index (non-compact) and optional summary
            let display_name = if self.compact {
                entry.name.clone()
            } else {
                let name_with_index = format!("{}:{}", entry.name, entry.window_index);
                match &entry.summary {
                    Some(summary) => format!("{} <{}>", name_with_index, summary),
                    None => name_with_index,
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

            if !self.compact {
                match entry.state {
                    ClaudeState::Active => {
                        let todo_str = match &entry.active_todo {
                            Some(todo) => format!("[{}]", todo),
                            None => "[]".to_string(),
                        };
                        write!(f, "  {}", todo_str)?;
                    }
                    ClaudeState::Draft => {
                        let draft_str = match &entry.draft_content {
                            Some(draft) => format!("> {}", draft),
                            None => "> ".to_string(),
                        };
                        write!(f, "  {}", draft_str)?;
                    }
                    _ => {}
                }
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

// Only use ollama when --llm-summaries is passed
static USE_LLM_SUMMARIES: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Generate a short summary using ollama chat API with conversation format
fn generate_summary_with_llm(first_message: &str) -> Option<String> {
    // Only run if --llm-summaries was passed
    if !USE_LLM_SUMMARIES.load(std::sync::atomic::Ordering::Relaxed) {
        return None;
    }

    // Get first line and truncate if too long
    let first_line = first_message.lines().next().unwrap_or(first_message).trim();

    // Skip if too short or empty - not worth asking the model
    if first_line.len() < 5 {
        return None;
    }

    let truncated = if first_line.len() > 200 {
        &first_line[..200]
    } else {
        first_line
    };

    // Build conversation with system prompt and few-shot examples
    let request_body = format!(
        r#"{{"model":"gemma2:2b","stream":false,"messages":[
{{"role":"system","content":"Output ONLY a 3-5 word label. No explanations, no markdown, no extra text."}},
{{"role":"user","content":"add dark mode to settings"}},
{{"role":"assistant","content":"dark mode settings"}},
{{"role":"user","content":"fix the memory leak in worker"}},
{{"role":"assistant","content":"fix worker memory leak"}},
{{"role":"user","content":"{}"}}
]}}"#,
        truncated.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', " ")
    );

    let output = match Command::new("curl")
        .args([
            "-s",
            "http://localhost:11434/api/chat",
            "-d",
            &request_body,
        ])
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => {
            OLLAMA_UNAVAILABLE.store(true, std::sync::atomic::Ordering::Relaxed);
            return None;
        }
    };

    // Parse JSON response to get message.content
    let response = String::from_utf8_lossy(&output.stdout);
    let summary = serde_json::from_str::<serde_json::Value>(&response)
        .ok()
        .and_then(|v| v.get("message")?.get("content")?.as_str().map(|s| {
            // Clean up: get first line, strip markdown/code blocks
            s.lines()
                .next()
                .unwrap_or(s)
                .trim()
                .trim_start_matches(['`', '#', '*', '-'])
                .trim()
                .to_string()
        }))
        .unwrap_or_default();

    // Reject bad outputs: empty, meta-commentary, conversational, too short, or too long (>5 words)
    let lower = summary.to_lowercase();
    let word_count = summary.split_whitespace().count();
    let is_bad = summary.is_empty()
        || summary.len() < 3
        || word_count > 5
        || summary.starts_with('(')
        || summary.contains("```")
        || lower.contains("request")
        || lower.contains("complex")
        || lower.contains("here's")
        || lower.starts_with("yes")
        || lower.starts_with("no")
        || lower.starts_with("i ")
        || lower.starts_with("this ")
        || lower.starts_with("the ")
        || lower.contains("already");
    if is_bad {
        None
    } else {
        // Limit length to 35 chars for display
        let max_len = 35;
        if summary.len() > max_len {
            Some(format!("{}...", &summary[..max_len]))
        } else {
            Some(summary)
        }
    }
}

/// Deserialize summary entries from session file
#[derive(Deserialize)]
struct SummaryEntry {
    #[serde(rename = "type")]
    entry_type: String,
    summary: Option<String>,
}

/// Get a short summary from the session file
/// Priority: 1. Summary entries (Claude-generated), 2. LLM summary of first message, 3. First user message
fn get_session_summary(session_file: &Path) -> Option<String> {
    use std::io::{BufRead, BufReader};

    let file = fs::File::open(session_file).ok()?;
    let reader = BufReader::new(file);

    let mut last_summary: Option<String> = None;
    let mut first_user_message: Option<String> = None;

    // Read ALL lines to find the last summary entry and first user message
    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };

        // Track summary entries - we want the LAST one (most recent)
        if line.contains("\"type\":\"summary\"") {
            if let Ok(entry) = serde_json::from_str::<SummaryEntry>(&line) {
                if entry.entry_type == "summary" {
                    if let Some(s) = entry.summary {
                        last_summary = Some(s);
                    }
                }
            }
        }

        // Track first user message as fallback (only need the first one)
        if first_user_message.is_none() && line.contains("\"type\":\"user\"") {
            if let Ok(msg) = serde_json::from_str::<SessionMessage>(&line) {
                if msg.msg_type == "user" {
                    if let Some(content) = msg.message {
                        if content.role == "user" {
                            first_user_message = Some(content.content.trim().to_string());
                        }
                    }
                }
            }
        }
    }

    // Prefer summary entries (Claude-generated)
    if let Some(s) = last_summary {
        let max_len = 50;
        return if s.len() > max_len {
            Some(format!("{}...", &s[..max_len]))
        } else {
            Some(s)
        };
    }

    // Fall back to first user message
    if let Some(first_message) = first_user_message {
        // Try to generate summary with LLM
        if let Some(summary) = generate_summary_with_llm(&first_message) {
            return Some(summary);
        }

        // Fallback: use truncated first line of message with ". " prefix
        let first_line = first_message.lines().next().unwrap_or(&first_message);
        let max_len = 47; // 50 - 3 for ". " prefix
        return if first_line.len() > max_len {
            Some(format!(". {}...", &first_line[..max_len]))
        } else {
            Some(format!(". {}", first_line))
        };
    }

    None
}

/// Check if a session file has actual conversation content (not just file-history-snapshot)
fn session_has_conversation(path: &Path) -> bool {
    use std::io::{BufRead, BufReader};

    let file = match fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return false,
    };
    let reader = BufReader::new(file);

    for line in reader.lines().take(50) {
        if let Ok(line) = line {
            // Quick check for user message type
            if line.contains("\"type\":\"user\"") {
                return true;
            }
            // Also check for summary type (indicates real conversation)
            if line.contains("\"type\":\"summary\"") {
                return true;
            }
        }
    }
    false
}

/// Extract a unique identifier from tmux pane content that can be matched to a session
fn extract_session_fingerprint(tmux_target: &str) -> Option<String> {
    let output = Command::new("tmux")
        .args(["capture-pane", "-t", tmux_target, "-p", "-S", "-500"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let content = String::from_utf8_lossy(&output.stdout);

    // Strategy 1: Find the FIRST user message in the conversation (most unique)
    // Look for the pattern after the welcome screen / initial prompt
    // User messages appear as "> message text" but we want the earliest one
    for line in content.lines() {
        let trimmed = line.trim();

        // Skip empty lines and suggestions
        if trimmed.is_empty() {
            continue;
        }

        // User prompt lines start with "> "
        if trimmed.starts_with("> ") && trimmed.len() > 15 {
            let msg = &trimmed[2..]; // Skip "> "

            // Skip suggestions and meta-text
            if msg.starts_with("Try ") || msg.contains("bypass") || msg.starts_with("──") {
                continue;
            }

            // This looks like an actual user message - use first 40 chars as fingerprint
            // The first user message is usually unique to this session
            let fingerprint = if msg.len() > 40 { &msg[..40] } else { msg };
            return Some(fingerprint.to_string());
        }
    }

    // Strategy 2: Look for Claude's response patterns with unique paths
    for line in content.lines() {
        // Look for file operations with full paths (more unique)
        if line.contains("Update(") || line.contains("Write(") {
            if let Some(start) = line.find('(') {
                if let Some(end) = line.find(')') {
                    let inner = &line[start + 1..end];
                    // Only use paths, not short commands
                    if inner.contains('/') && inner.len() > 20 {
                        return Some(inner.to_string());
                    }
                }
            }
        }
    }

    None
}

/// Find session file by matching screen content fingerprint in USER messages
/// Returns the OLDEST matching file (by creation time) since that's likely the original source
fn find_session_by_fingerprint(project_dir: &Path, fingerprint: &str) -> Option<PathBuf> {
    use std::io::{BufRead, BufReader};

    let entries = fs::read_dir(project_dir).ok()?;

    let mut matches: Vec<(PathBuf, std::time::SystemTime)> = Vec::new();

    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if !name_str.ends_with(".jsonl") || name_str.starts_with("agent-") {
            continue;
        }

        let path = entry.path();

        // Search for fingerprint specifically in user messages
        let file = match fs::File::open(&path) {
            Ok(f) => f,
            Err(_) => continue,
        };
        let reader = BufReader::new(file);

        let mut found_in_user_msg = false;
        for line in reader.lines().take(100) {
            if let Ok(line) = line {
                // Only match in user message lines
                if line.contains("\"type\":\"user\"") && line.contains(fingerprint) {
                    found_in_user_msg = true;
                    break;
                }
            }
        }

        if found_in_user_msg {
            if let Ok(metadata) = fs::metadata(&path) {
                if let Ok(created) = metadata.created() {
                    matches.push((path, created));
                }
            }
        }
    }

    // Sort by creation time (oldest first) - the original session
    matches.sort_by_key(|(_, created)| *created);
    matches.first().map(|(path, _)| path.clone())
}

/// Find session file for a project by matching to process start time
/// For resumed sessions, uses screen content matching as fallback
fn find_session_file_for_process(project_dir: &Path, process_start: Option<std::time::SystemTime>, tmux_target: &str) -> Option<PathBuf> {
    let entries = fs::read_dir(project_dir).ok()?;

    let mut session_files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            name_str.ends_with(".jsonl") && !name_str.starts_with("agent-")
        })
        .filter_map(|e| {
            let path = e.path();
            let metadata = e.metadata().ok()?;
            let modified = metadata.modified().ok()?;
            let created = metadata.created().ok();
            Some((path, created, modified))
        })
        .collect();

    if let Some(proc_start) = process_start {
        // Strategy 1: Find sessions CREATED after process start with conversation content
        // This is the most reliable - a new session file was created for this process
        let mut new_sessions: Vec<_> = session_files
            .iter()
            .filter_map(|(path, created, _)| {
                let created = (*created)?;
                if created >= proc_start {
                    let diff = created.duration_since(proc_start).ok()?;
                    if diff.as_secs() <= 60 && session_has_conversation(path) {
                        return Some((path.clone(), diff));
                    }
                }
                None
            })
            .collect();

        new_sessions.sort_by_key(|(_, diff)| *diff);

        if let Some((path, _)) = new_sessions.first() {
            return Some(path.clone());
        }

        // Strategy 2: For resumed sessions, use screen content fingerprinting
        // This finds the original session file by matching visible conversation content
        if let Some(fingerprint) = extract_session_fingerprint(tmux_target) {
            if let Some(path) = find_session_by_fingerprint(project_dir, &fingerprint) {
                return Some(path);
            }
        }

        // Strategy 3: Find sessions MODIFIED after process start (active writing)
        // Only use this if fingerprinting failed
        let mut active_sessions: Vec<_> = session_files
            .iter()
            .filter(|(_, _, modified)| *modified >= proc_start)
            .filter(|(path, _, _)| session_has_conversation(path))
            .map(|(path, _, modified)| (path.clone(), *modified))
            .collect();

        active_sessions.sort_by(|a, b| b.1.cmp(&a.1));

        if let Some((path, _)) = active_sessions.first() {
            return Some(path.clone());
        }
    }

    // Fallback: return most recently modified with conversation content
    session_files.sort_by(|a, b| b.2.cmp(&a.2));
    session_files
        .iter()
        .find(|(path, _, _)| session_has_conversation(path))
        .map(|(path, _, _)| path.clone())
}

/// Get process start time from /proc/PID/stat
fn get_process_start_time(pid: u32) -> Option<std::time::SystemTime> {
    // Read starttime (field 22) from /proc/PID/stat - it's in clock ticks since boot
    let stat_content = fs::read_to_string(format!("/proc/{}/stat", pid)).ok()?;
    let fields: Vec<&str> = stat_content.split_whitespace().collect();
    if fields.len() < 22 {
        return None;
    }
    let starttime_ticks: u64 = fields[21].parse().ok()?;

    // Get system boot time from /proc/stat
    let proc_stat = fs::read_to_string("/proc/stat").ok()?;
    let btime_line = proc_stat.lines().find(|l| l.starts_with("btime "))?;
    let boot_time: u64 = btime_line.split_whitespace().nth(1)?.parse().ok()?;

    // Clock ticks per second (usually 100 on Linux)
    let ticks_per_sec: u64 = 100; // Could use sysconf(_SC_CLK_TCK) but 100 is standard

    let start_secs = boot_time + (starttime_ticks / ticks_per_sec);
    Some(std::time::UNIX_EPOCH + std::time::Duration::from_secs(start_secs))
}

/// Get session info (todo and summary) for a tmux pane
fn get_session_info_for_pane(shell_pid: u32, tmux_target: &str) -> (Option<String>, Option<String>) {
    let info = (|| -> Option<(Option<String>, Option<String>)> {
        let claude_pid = get_child_pid(shell_pid)?;
        let cwd = get_process_cwd(claude_pid)?;
        let project_name = path_to_project_name(&cwd);

        let home = std::env::var("HOME").ok()?;
        let project_dir = PathBuf::from(&home)
            .join(".claude/projects")
            .join(&project_name);

        // Get process start time to match with session file
        let proc_start = get_process_start_time(claude_pid);
        let session_file = find_session_file_for_process(&project_dir, proc_start, tmux_target)?;
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

        // Window must have "claude" in its name OR the pane command must be "claude"
        let is_claude_window = window_name.eq("claude") || window_name.starts_with("claude") || window_name.contains("claude");
        let is_claude_pane = pane_command == "claude";
        if !is_claude_window && !is_claude_pane {
            continue;
        }

        let tmux_target = format!("{}:{}", session, window_index);
        let (state, active_todo, draft_content, summary) = if pane_command == "claude" {
            // Claude is running, check if active or finished
            let activity = determine_claude_activity(session, window_index);
            let (active_todo, summary) = if activity.state == ClaudeState::Active {
                get_session_info_for_pane(pane_pid, &tmux_target)
            } else {
                // Still get summary for non-active states
                let (_, summary) = get_session_info_for_pane(pane_pid, &tmux_target);
                (None, summary)
            };
            (activity.state, active_todo, activity.draft_content, summary)
        } else {
            (ClaudeState::Empty, None, None, None)
        };

        claude_windows.push(ClaudeWindow {
            session: session.to_string(),
            window_index,
            state,
            active_todo,
            draft_content,
            summary,
        });
    }

    claude_windows
}

/// Result of activity detection including state and optional draft content
struct ActivityResult {
    state: ClaudeState,
    draft_content: Option<String>,
}

fn determine_claude_activity(session: &str, window_index: u32) -> ActivityResult {
    let target = format!("{}:{}", session, window_index);

    let output = Command::new("tmux")
        .args(["capture-pane", "-t", &target, "-p", "-S", "-50"])
        .output();

    let content = match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
        _ => return ActivityResult { state: ClaudeState::Finished, draft_content: None },
    };

    // Look at the last portion for various indicators
    // Filter empty lines first, then take last 15 non-empty lines
    let last_portion: String = content
        .lines()
        .rev()
        .filter(|l| !l.trim().is_empty())
        .take(15)
        .collect::<Vec<_>>()
        .join("\n");

    // Check if there's a prompt line at the very end (last few non-empty lines)
    // If so, Claude is waiting for input even if there's spinner text from earlier
    let last_few_lines: Vec<&str> = content
        .lines()
        .rev()
        .filter(|l| !l.trim().is_empty())
        .take(5)
        .collect();

    let has_prompt_at_end = last_few_lines.iter().any(|l| l.starts_with("> "));

    // Match spinner pattern: "Word…" (capitalized word followed by ellipsis)
    // Examples: Running…, Thinking…, Cogitating…, Summarizing…
    // Only match if there's no prompt at the end (meaning Claude is still working)
    let spinner_pattern = Regex::new(r"[A-Z][a-z]+…").unwrap();

    if spinner_pattern.is_match(&last_portion) && !has_prompt_at_end {
        return ActivityResult { state: ClaudeState::Active, draft_content: None };
    }

    // Check for external editor with claude-prompt temp file
    // When user opens external editor (nvim, vim, etc), Claude creates a temp file
    // like /tmp/claude-prompt-*.md - if we see this in the pane, it's a draft
    // Match only at start of line (nvim title bar) to avoid false positives from text mentioning the file
    let claude_prompt_pattern = Regex::new(r"(?m)^[/ ]*t.*/claude-prompt-([a-f0-9-]+)\.md").unwrap();
    if let Some(caps) = claude_prompt_pattern.captures(&content) {
        let uuid = &caps[1];
        let full_path = format!("/tmp/claude-prompt-{}.md", uuid);
        // Read the temp file contents for draft display
        let draft_content = fs::read_to_string(&full_path)
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .map(|s| {
                // Get first line and truncate if needed
                let first_line = s.lines().next().unwrap_or(&s);
                if first_line.len() > 50 {
                    format!("{}...", &first_line[..50])
                } else {
                    first_line.to_string()
                }
            });
        return ActivityResult {
            state: ClaudeState::Draft,
            draft_content,
        };
    }

    // Check for draft state: user has typed something after "> "
    // The bypass permissions prompt is visible and there's actual text after "> "
    // Note: We need to distinguish real input from grey suggestions (dim text)
    // This must come BEFORE the fresh session check, as user may type on welcome screen
    if last_portion.contains("bypass permissions") {
        // Re-capture with escape codes to detect dim text (suggestions)
        let output_with_escapes = Command::new("tmux")
            .args(["capture-pane", "-t", &target, "-p", "-e", "-S", "-10"])
            .output();

        if let Ok(out) = output_with_escapes {
            let content_esc = String::from_utf8_lossy(&out.stdout);
            // Find the current prompt line - it has "[0m>" pattern (reset then prompt)
            // The prompt may be followed by regular space or NBSP
            if let Some(prompt_line) = content_esc.lines().find(|l| l.contains("\x1b[0m>"))
            {
                if let Some(pos) = prompt_line.find("\x1b[0m>") {
                    let after_gt = &prompt_line[pos + 5..]; // 5 = len of "\x1b[0m>"
                    // Check if this is a suggestion vs real user input
                    // Suggestions have dim text (\x1b[...2m), possibly with cursor highlight (\x1b[7m) on first char
                    // Real input has regular text without dim escapes
                    // Note: dim can be "\x1b[2m" or combined like "\x1b[0;2m"
                    let dim_pattern = Regex::new(r"\x1b\[[0-9;]*2m").unwrap();
                    let reverse_pattern = Regex::new(r"\x1b\[7m").unwrap();
                    // It's a suggestion if: has dim text OR (has reverse video followed by dim)
                    // which indicates cursor is highlighting a suggestion character
                    let has_dim = dim_pattern.is_match(after_gt);
                    let has_reverse_then_dim = reverse_pattern.is_match(after_gt) && has_dim;
                    let is_suggestion = has_dim || has_reverse_then_dim;
                    let has_content = after_gt.chars().any(|c| c.is_alphanumeric());
                    if has_content && !is_suggestion {
                        // Extract the actual draft text (strip escape codes)
                        let escape_pattern = Regex::new(r"\x1b\[[0-9;]*m").unwrap();
                        let clean_text = escape_pattern.replace_all(after_gt, "");
                        // Also strip NBSP and trim
                        let draft_text = clean_text.replace('\u{00A0}', " ").trim().to_string();
                        // Truncate if too long
                        let draft_display = if draft_text.len() > 50 {
                            format!("{}...", &draft_text[..50])
                        } else {
                            draft_text
                        };
                        return ActivityResult {
                            state: ClaudeState::Draft,
                            draft_content: if draft_display.is_empty() { None } else { Some(draft_display) },
                        };
                    }
                }
            }
        }
    }

    // Check for fresh session (welcome screen) - after draft check
    if content.contains("No recent activity") || content.contains("Tips for getting started") {
        return ActivityResult { state: ClaudeState::Empty, draft_content: None };
    }

    // Check if there's an input prompt line ("> ") - indicates waiting for input
    let has_prompt = content.lines().any(|line| line.starts_with("> "));
    if has_prompt {
        return ActivityResult { state: ClaudeState::Finished, draft_content: None };
    }

    // Check for error patterns (rate limit, panics, errors)
    let error_pattern = Regex::new(r"(?i)(rate.?limit|error:|panicked|PANIC|timed.?out)").unwrap();

    if error_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Error, draft_content: None };
    }

    ActivityResult { state: ClaudeState::Finished, draft_content: None }
}

fn main() {
    let args = Args::parse();

    // Set LLM summaries flag
    if args.llm_summaries {
        USE_LLM_SUMMARIES.store(true, std::sync::atomic::Ordering::Relaxed);
    }

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
    results.sort_by(|a, b| {
        a.session
            .cmp(&b.session)
            .then(a.window_index.cmp(&b.window_index))
    });

    // Build Sessions struct
    let mut sessions = Sessions::new(args.compact);
    for window in results {
        sessions.add(SessionEntry {
            name: window.session.clone(),
            window_index: window.window_index,
            state: window.state,
            active_todo: window.active_todo.clone(),
            draft_content: window.draft_content.clone(),
            summary: window.summary.clone(),
        });
    }
    sessions.sort();

    // Show warning if ollama was unavailable (only in non-compact mode with summaries)
    if !args.compact && !args.json && OLLAMA_UNAVAILABLE.load(std::sync::atomic::Ordering::Relaxed)
    {
        eprintln!(
            "{}",
            "warn: ollama unavailable, using fallback summaries".yellow()
        );
    }

    if args.json {
        println!("{}", serde_json::to_string(&sessions.entries).unwrap());
    } else {
        println!("{}", sessions);
    }
}
