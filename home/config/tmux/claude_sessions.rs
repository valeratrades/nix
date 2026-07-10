#!/home/v/nix/home/scripts/nix-run-cached
---cargo
[dependencies]
clap = { version = "4.5.49", features = ["derive"] }
colored = "2"
regex = "1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[dev-dependencies]
insta = "1"
---

use clap::Parser;
use colored::Colorize;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
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

    /// Emit Pango markup (for eww labels) instead of ANSI terminal colors.
    /// eww is a GTK surface, not a terminal — ANSI escapes are inert there, so
    /// attention-coloring has to ride in as <span foreground=...> tags instead.
    #[arg(long)]
    markup: bool,

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
    Question, // Claude is asking a question (numbered options visible)
    Input,    // User has typed text into the live input box (not yet sent)
    Error,    // Claude hit an error (rate limit, panic, etc.)
    Limit,    // Session usage limit hit ("You've hit your session limit · resets ...")
    Interrupted, // User aborted the turn (esc); dropped back to a live prompt
}

impl ClaudeState {
    /// The pane's Finished reading flip-flops between tool calls; the transcript
    /// verdict is authoritative, active todos are the fallback when it abstains.
    /// Lives here (not inline in get_claude_windows) so the fixture tests replay
    /// the exact production deliberation.
    fn refine_finished(transcript_working: Option<bool>, has_active_todos: bool) -> ClaudeState {
        if transcript_working.unwrap_or(has_active_todos) {
            ClaudeState::Active
        } else {
            ClaudeState::Finished
        }
    }

    fn as_str(&self) -> &'static str {
        match self {
            ClaudeState::Empty => "empty",
            ClaudeState::Active => "active",
            ClaudeState::Finished => "finished",
            ClaudeState::Draft => "draft",
            ClaudeState::Question => "question",
            ClaudeState::Input => "input",
            ClaudeState::Error => "error",
            ClaudeState::Limit => "limit",
            ClaudeState::Interrupted => "interrupted",
        }
    }
}

#[derive(Debug)]
struct ClaudeWindow {
    session: String,
    window_index: u32,
    state: ClaudeState,
    /// A claude process is live in the pane. Distinguishes a fresh-but-real
    /// session (Empty state, welcome screen) from a claude-NAMED window that's
    /// just sitting at a shell — only the latter get deduped away in main().
    claude_running: bool,
    active_todo: Option<String>,
    draft_content: Option<String>,
    question_content: Option<String>,
    summary: Option<String>,
}

#[derive(Debug, Serialize)]
struct SessionEntry {
    name: String,
    window_index: u32,
    state: ClaudeState,
    active_todo: Option<String>,
    draft_content: Option<String>,
    question_content: Option<String>,
    summary: Option<String>,
}

#[derive(Debug)]
struct Sessions {
    entries: Vec<SessionEntry>,
    compact: bool,
    markup: bool,
}

impl Sessions {
    fn new(compact: bool, markup: bool) -> Self {
        Self {
            entries: Vec::new(),
            compact,
            markup,
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

            // Pad state string manually since colored strings mess up format width.
            // Pad to VISIBLE width first; coloring (ANSI or Pango span) is applied
            // after, so it never participates in width math.
            let state_str = entry.state.as_str();
            let padded_state = format!("{:width$}", state_str, width = max_state_len);

            // The name column is likewise padded to visible width before any
            // escaping — Pango escaping changes byte length but not glyph count,
            // so escaping after padding keeps the columns aligned.
            let padded_name = format!("{:width$}", display_name, width = max_name_len);

            // Trailing per-state content (todo / draft / question), if any.
            let trailing = if self.compact {
                None
            } else {
                match entry.state {
                    ClaudeState::Active => Some(match &entry.active_todo {
                        Some(todo) => format!("[{}]", todo),
                        None => "[]".to_string(),
                    }),
                    ClaudeState::Draft => Some(match &entry.draft_content {
                        Some(draft) => format!("> {}", draft),
                        None => "> ".to_string(),
                    }),
                    ClaudeState::Question => Some(match &entry.question_content {
                        Some(q) => format!("? {}", q),
                        None => "?".to_string(),
                    }),
                    _ => None,
                }
            };

            if self.markup {
                // eww/GTK path: escape every literal segment for Pango, then wrap
                // the state cell in a <span> only for the states that warrant
                // grabbing my eye. Attention priority, NOT prettiness:
                //   question -> error red  (#ff6565): a session is BLOCKED on me,
                //               nothing moves until I act — highest visual urgency.
                //   error    -> warn brown (#ba6e3d): real, but errors here mostly
                //               surface during hands-on interaction, so I'm already
                //               looking — deliberately ranked below question.
                //   active   -> blue       (#68d4ff): healthy "it's working" signal,
                //               informational, lowest of the three.
                //   limit    -> white      (#ffffff): wedged on the usage clock —
                //               nothing to act on, but worth seeing at a glance.
                //   finished -> faint green (#b8d8b4): oklch(0.85 0.06 142), green
                //               with chroma pulled near grey — distinguishable from
                //               empty without popping.
                // Every other state stays uncolored — no span, no noise.
                let state_cell = match entry.state {
                    ClaudeState::Question => {
                        format!("<span foreground=\"#ff6565\">{}</span>", pango_escape(&padded_state))
                    }
                    ClaudeState::Limit | ClaudeState::Input => {
                        format!("<span foreground=\"#ffffff\">{}</span>", pango_escape(&padded_state))
                    }
                    ClaudeState::Error => {
                        format!("<span foreground=\"#ba6e3d\">{}</span>", pango_escape(&padded_state))
                    }
                    ClaudeState::Active => {
                        format!("<span foreground=\"#68d4ff\">{}</span>", pango_escape(&padded_state))
                    }
                    ClaudeState::Finished => {
                        format!("<span foreground=\"#b8d8b4\">{}</span>", pango_escape(&padded_state))
                    }
                    _ => pango_escape(&padded_state),
                };
                write!(f, "{}  {}", pango_escape(&padded_name), state_cell)?;
                if let Some(t) = trailing {
                    write!(f, "  {}", pango_escape(&t))?;
                }
            } else {
                // Terminal path: ANSI colors via `colored`, unchanged.
                let colored_state = match entry.state {
                    ClaudeState::Active => padded_state.blue(),
                    ClaudeState::Finished => padded_state.green(),
                    ClaudeState::Empty => padded_state.yellow(),
                    ClaudeState::Draft => padded_state.cyan(),
                    ClaudeState::Question => padded_state.magenta(),
                    ClaudeState::Error => padded_state.red(),
                    ClaudeState::Limit | ClaudeState::Input => padded_state.white(),
                    ClaudeState::Interrupted => padded_state.normal(),
                };
                write!(f, "{}  {}", padded_name, colored_state)?;
                if let Some(t) = trailing {
                    write!(f, "  {}", t)?;
                }
            }
        }
        Ok(())
    }
}

/// Escape text so Pango parses it as literal content, not markup. eww feeds the
/// label through Pango when markup is on, so any raw `<`, `>`, `&` in session
/// names, todos, or summaries (e.g. the `<summary>` brackets, `> draft`, `? q`)
/// would otherwise be read as broken tags and blank the whole label.
fn pango_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
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
    path.to_string_lossy().replace('/', "-").replace('_', "-")
}

/// Find todo files matching a session ID and get todo status
/// Returns (has_active_todos, display_todo)
fn get_active_todo_from_session(session_id: &str) -> TodoResult {
    let home = match std::env::var("HOME") {
        Ok(h) => h,
        Err(_) => return TodoResult { has_active_todos: false, display_todo: None },
    };
    let todos_dir = PathBuf::from(home).join(".claude/todos");

    let entries = match fs::read_dir(&todos_dir) {
        Ok(e) => e,
        Err(_) => return TodoResult { has_active_todos: false, display_todo: None },
    };

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

    // Try each todo file until we find active todos
    for (path, _) in todo_files {
        let result = read_active_todo(&path);
        if result.has_active_todos {
            return result;
        }
    }

    TodoResult { has_active_todos: false, display_todo: None }
}

/// Result of reading a todo file
struct TodoResult {
    /// Whether any non-completed todos exist (session is active)
    has_active_todos: bool,
    /// The todo to display (in_progress, or first pending if no completed yet)
    display_todo: Option<String>,
}

/// Read a todo file and determine activity status
/// Returns (has_active_todos, display_todo)
/// - has_active_todos: true if any pending/in_progress todos exist
/// - display_todo: in_progress > first pending (if no completed) > None
fn read_active_todo(path: &Path) -> TodoResult {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return TodoResult { has_active_todos: false, display_todo: None },
    };
    let todos: Vec<TodoItem> = match serde_json::from_str(&content) {
        Ok(t) => t,
        Err(_) => return TodoResult { has_active_todos: false, display_todo: None },
    };

    // Empty array means all todos were completed and cleared
    if todos.is_empty() {
        return TodoResult { has_active_todos: false, display_todo: None };
    }

    // Check if there are any non-completed todos (pending or in_progress)
    let has_active_todos = todos.iter().any(|t| t.status != "completed");

    // First priority: explicit in_progress
    if let Some(t) = todos.iter().find(|t| t.status == "in_progress") {
        return TodoResult {
            has_active_todos,
            display_todo: Some(t.active_form.clone()),
        };
    }

    // If any completed exist, Claude has started working through the list
    // but hasn't marked next as in_progress yet - don't show stale pending
    let has_completed = todos.iter().any(|t| t.status == "completed");
    if has_completed {
        return TodoResult { has_active_todos, display_todo: None };
    }

    // No completed yet = Claude just created the list, show first pending
    let display_todo = todos
        .iter()
        .find(|t| t.status == "pending")
        .map(|t| t.active_form.clone());

    TodoResult { has_active_todos, display_todo }
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

/// Deterministic idle check from the transcript, deciding the flip-floppy
/// active↔finished case the terminal can't. Returns:
///   Some(true)  — work in flight (last message is a pending tool_use, or a user
///                 message whose assistant reply hasn't landed yet)
///   Some(false) — genuinely idle (last message is a completed assistant turn)
///   None        — undetermined (no message in the tail); caller falls back
///
/// Only the tail is read: transcripts reach tens of MB, but the last message is
/// near the end. ponytail: 256KB window; a single message can't exceed it in
/// practice (largest observed line ~35KB), and if it somehow does we return None.
fn transcript_working(session_file: &Path) -> Option<bool> {
    const TAIL_BYTES: u64 = 256 * 1024;
    let mut file = fs::File::open(session_file).ok()?;
    let len = file.metadata().ok()?.len();
    let start = len.saturating_sub(TAIL_BYTES);
    file.seek(SeekFrom::Start(start)).ok()?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).ok()?;
    let buf = String::from_utf8_lossy(&bytes); // tail seek may split a char/line

    let mut lines = buf.lines();
    if start > 0 {
        lines.next(); // first line is likely a partial record
    }
    for line in lines.collect::<Vec<_>>().into_iter().rev() {
        let v: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let entry_type = v.get("type").and_then(|x| x.as_str()).unwrap_or("");
        if entry_type != "user" && entry_type != "assistant" {
            continue;
        }
        let role = v
            .get("message")
            .and_then(|m| m.get("role"))
            .and_then(|x| x.as_str())
            .unwrap_or(entry_type);
        return Some(if role == "assistant" {
            // A completed turn ends with a non-tool stop_reason; "tool_use" means
            // a tool call is outstanding, i.e. still working.
            v.get("message").and_then(|m| m.get("stop_reason")).and_then(|x| x.as_str()) == Some("tool_use")
        } else {
            // Last message is the user's — assistant reply is still pending.
            true
        });
    }
    None
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

    // A visible user message is the fingerprint — its text exists verbatim in
    // exactly the transcripts that contain that conversation. v2 renders past
    // user messages as "❯ message" (regular space; the live input box uses an
    // NBSP and is deliberately NOT matched — unsent text exists in no file);
    // older builds used "> ". Nothing else is a safe fingerprint: file paths /
    // tool banners repeat across every session working in the same cwd, and
    // matching on those attributed windows to their neighbours' transcripts.
    // The LAST visible message wins: the matcher scans each transcript's head
    // and 256KB tail, and in a long session only the most RECENT messages are
    // still within the tail window — the earliest visible one can sit megabytes
    // before EOF.
    let mut fingerprint = None;
    let selector_row = Regex::new(r"^\d+\.\s").unwrap();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.len() <= 15 {
            continue;
        }

        let Some(msg) = trimmed
            .strip_prefix("> ")
            .or_else(|| trimmed.strip_prefix("❯ "))
        else {
            continue;
        };

        // Skip suggestions, meta-text, and selector rows ("❯ 1. Option") — the
        // ❯ glyph doubles as the selection cursor.
        if msg.starts_with("Try ")
            || msg.contains("bypass")
            || msg.starts_with("──")
            || selector_row.is_match(msg)
        {
            continue;
        }

        // User messages are usually unique to their session; 40 chars is
        // plenty of entropy while staying inside one rendered line.
        fingerprint = Some(msg.chars().take(40).collect::<String>());
    }

    fingerprint
}

/// Find session file by matching screen content fingerprint in USER messages
/// Returns the OLDEST matching file (by creation time) since that's likely the original source
///
/// Both ends of each transcript are searched: the head holds a session's opening
/// messages (all a short/fresh session has), while for a LONG session the pane
/// shows recent messages — which live in the tail, far past any head window.
fn find_session_by_fingerprint(project_dir: &Path, fingerprint: &str) -> Option<PathBuf> {
    use std::io::{BufRead, BufReader};

    let entries = fs::read_dir(project_dir).ok()?;

    let mut matches: Vec<(PathBuf, std::time::SystemTime)> = Vec::new();

    // Genuine typed messages only: tool_result entries are ALSO type "user", and
    // they embed captured pane text — without this filter a session that ran
    // this very script (or read another's pane) would claim its neighbours'
    // fingerprints.
    let is_user_hit = |line: &str| {
        line.contains("\"type\":\"user\"")
            && !line.contains("tool_use_id")
            && line.contains(fingerprint)
    };

    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if !name_str.ends_with(".jsonl") || name_str.starts_with("agent-") {
            continue;
        }

        let path = entry.path();

        let file = match fs::File::open(&path) {
            Ok(f) => f,
            Err(_) => continue,
        };
        let mut found = BufReader::new(file)
            .lines()
            .take(100)
            .map_while(Result::ok)
            .any(|l| is_user_hit(&l));

        if !found {
            // Tail window, same size rationale as transcript_working.
            found = (|| -> Option<bool> {
                let mut file = fs::File::open(&path).ok()?;
                let len = file.metadata().ok()?.len();
                file.seek(SeekFrom::Start(len.saturating_sub(256 * 1024))).ok()?;
                let mut bytes = Vec::new();
                file.read_to_end(&mut bytes).ok()?;
                Some(String::from_utf8_lossy(&bytes).lines().any(|l| is_user_hit(l)))
            })()
            .unwrap_or(false);
        }

        if found {
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
///
/// Attribution here must be conservative: several live claude processes can
/// share one cwd (and thus one project dir), and a transcript attributed to the
/// wrong window poisons everything downstream — its summary, its todos, and the
/// transcript-based active↔finished verdict. None is strictly better than a
/// neighbour's file.
fn find_session_file_for_process(project_dir: &Path, process_start: Option<std::time::SystemTime>, tmux_target: &str) -> Option<PathBuf> {
    // Without /proc visibility of the process there is nothing to anchor
    // attribution to — every heuristic below degenerates into "some file in
    // this dir", i.e. a guess.
    let proc_start = process_start?;
    let entries = fs::read_dir(project_dir).ok()?;

    let session_files: Vec<_> = entries
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

    // Strategy 1: Find sessions CREATED shortly after process start — a new
    // session file was created for this process. The 60s window is what keeps
    // this from stealing files that a LATER-started neighbour created in the
    // same dir. (v2 creates the .jsonl lazily on first message, so a fresh
    // untouched session has NO file at all and correctly matches nothing.)
    let mut new_sessions: Vec<_> = session_files
        .iter()
        .filter_map(|(path, created, _)| {
            let created = (*created)?;
            if created >= proc_start {
                let diff = created.duration_since(proc_start).ok()?;
                if diff.as_secs() <= 60 {
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

    // Strategy 3: sessions MODIFIED after process start. mtime records only the
    // LAST write, so with several live sessions in one cwd all of their files
    // pass this filter — and picking "most recent" handed every window the
    // busiest neighbour's transcript (wrong summary, wrong active↔finished
    // verdict). Only an unambiguous single candidate is trustworthy.
    let candidates: Vec<_> = session_files
        .iter()
        .filter(|(_, _, modified)| *modified >= proc_start)
        .filter(|(path, _, _)| session_has_conversation(path))
        .collect();

    if let [(path, _, _)] = candidates.as_slice() {
        return Some(path.clone());
    }

    None
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

/// Session metadata extracted from the session file
struct SessionMetadata {
    /// Whether any non-completed todos exist (session is actively working)
    has_active_todos: bool,
    /// The todo to display
    display_todo: Option<String>,
    /// Session summary
    summary: Option<String>,
    /// Transcript verdict on whether work is in flight (see transcript_working)
    transcript_working: Option<bool>,
}

/// Get session info (todo and summary) for a tmux pane
fn get_session_info_for_pane(shell_pid: u32, tmux_target: &str) -> Option<SessionMetadata> {
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

    let todo_result = get_active_todo_from_session(&session_id);
    let summary = get_session_summary(&session_file);

    Some(SessionMetadata {
        has_active_todos: todo_result.has_active_todos,
        display_todo: todo_result.display_todo,
        summary,
        transcript_working: transcript_working(&session_file),
    })
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
        let is_claude_pane = pane_command.contains("claude");
        if !is_claude_window && !is_claude_pane {
            continue;
        }

        let tmux_target = format!("{}:{}", session, window_index);
        let (state, active_todo, draft_content, question_content, summary) = if is_claude_pane {
            // Terminal parsing decides the blocking states (Question/Draft/Error)
            // and the working state, but active↔finished flip-flops between tool
            // calls when no spinner is captured. For that one reading we defer to
            // the transcript, which deterministically says whether a turn is still
            // in flight; active todos remain the fallback when it can't decide.
            let activity = determine_claude_activity(session, window_index);

            // Empty takes precedence over any transcript deliberation: a fresh
            // pane has no session file at all (v2 creates the .jsonl on first
            // message), so a metadata lookup could only mis-attribute a
            // neighbour's transcript to it.
            if activity.state == ClaudeState::Empty {
                (ClaudeState::Empty, None, None, None, None)
            } else {
                let metadata = get_session_info_for_pane(pane_pid, &tmux_target);
                let summary = metadata.as_ref().and_then(|m| m.summary.clone());

                match activity.state {
                    ClaudeState::Finished => {
                        let refined = ClaudeState::refine_finished(
                            metadata.as_ref().and_then(|m| m.transcript_working),
                            matches!(&metadata, Some(m) if m.has_active_todos),
                        );
                        if refined == ClaudeState::Active {
                            let todo = metadata.as_ref().and_then(|m| m.display_todo.clone());
                            (ClaudeState::Active, todo, None, None, summary)
                        } else {
                            (ClaudeState::Finished, None, None, None, summary)
                        }
                    }
                    _ => (
                        activity.state,
                        None,
                        activity.draft_content,
                        activity.question_content,
                        summary,
                    ),
                }
            }
        } else {
            // Claude-named window sitting at a shell. Usually a pre-created
            // empty slot — but if a claude EXITED here, its parting
            // "claude --resume <uuid>" chrome both marks the finished
            // conversation and names its transcript, so the session keeps its
            // summary after death. No transcript refinement for the dead:
            // nothing can be in flight there.
            let tail = Command::new("tmux")
                .args(["capture-pane", "-t", &tmux_target, "-p", "-S", "-50"])
                .output()
                .ok()
                .filter(|o| o.status.success())
                .map(|o| {
                    String::from_utf8_lossy(&o.stdout)
                        .lines()
                        .rev()
                        .filter(|l| !l.trim().is_empty())
                        .take(15)
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default();

            match dead_claude_resume_id(&tail) {
                Some(id) => {
                    let summary = get_process_cwd(pane_pid).and_then(|cwd| {
                        let home = std::env::var("HOME").ok()?;
                        let file = PathBuf::from(home)
                            .join(".claude/projects")
                            .join(path_to_project_name(&cwd))
                            .join(format!("{id}.jsonl"));
                        get_session_summary(&file)
                    });
                    (ClaudeState::Finished, None, None, None, summary)
                }
                None => (ClaudeState::Empty, None, None, None, None),
            }
        };

        claude_windows.push(ClaudeWindow {
            session: session.to_string(),
            window_index,
            state,
            claude_running: is_claude_pane,
            active_todo,
            draft_content,
            question_content,
            summary,
        });
    }

    claude_windows
}

/// Result of activity detection including state and optional draft/question content
#[derive(Debug)]
struct ActivityResult {
    state: ClaudeState,
    draft_content: Option<String>,
    question_content: Option<String>,
}

/// Session id from Claude Code's exit chrome ("Resume this session with:" /
/// "claude --resume <uuid>"). Anchored at line start: a user-TYPED resume
/// command sits after a prompt glyph and doesn't match.
fn dead_claude_resume_id(tail: &str) -> Option<String> {
    Regex::new(r"(?m)^claude --resume ([0-9a-f-]{36})\s*$")
        .unwrap()
        .captures_iter(tail)
        .last()
        .map(|c| c[1].to_string())
}

/// True if a captured line is Claude's "waiting for input" prompt. Modern
/// Claude Code prints "❯ " (U+276F); older builds printed "> ". The glyph sits
/// at the start of the line (after any leading box-chrome whitespace), so we
/// trim_start before matching — and require the trailing space so we don't trip
/// on a bare ">"/"❯" embedded in other output.
fn is_prompt_line(line: &str) -> bool {
    let t = line.trim_start();
    t.starts_with("> ") || t.starts_with("❯ ") || t.starts_with("❯\u{00A0}")
}

/// Text the user has typed into the live input box, if any. The input box is the
/// bottom-most prompt line; this returns its content with the prompt glyph and
/// surrounding whitespace/NBSP stripped, or None when the box is empty.
fn input_box_text(content: &str) -> Option<String> {
    let line = content.lines().rev().find(|l| is_prompt_line(l))?;
    let t = line.trim_start();
    let rest = t
        .strip_prefix("> ")
        .or_else(|| t.strip_prefix("❯ "))
        .or_else(|| t.strip_prefix("❯\u{00A0}"))?;
    let cleaned = rest.replace('\u{00A0}', " ").trim().to_string();
    (!cleaned.is_empty()).then_some(cleaned)
}

fn determine_claude_activity(session: &str, window_index: u32) -> ActivityResult {
    let target = format!("{}:{}", session, window_index);

    let output = Command::new("tmux")
        .args(["capture-pane", "-t", &target, "-p", "-S", "-50"])
        .output();

    let content = match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).to_string(),
        _ => return ActivityResult { state: ClaudeState::Finished, draft_content: None, question_content: None },
    };

    // The draft/dim-suggestion branch needs a SECOND, escape-coded capture to
    // tell real typed input from greyed-out ghost suggestions. It's only ever
    // consulted inside the "bypass permissions" branch, so we hand classify the
    // capture lazily — production pays the extra tmux call only when that branch
    // is reached, and tests can feed a fixture (or `|| None`) instead.
    classify_activity(&content, || {
        Command::new("tmux")
            .args(["capture-pane", "-t", &target, "-p", "-e", "-S", "-10"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
    })
}

/// Pure terminal-state classifier: the heart of this script and the source of
/// every historical regression. Given a plain `capture-pane -p` dump (`content`)
/// and a lazy provider for the escape-coded capture (`capture_escaped`, only
/// invoked in the draft branch), decide which `ClaudeState` the pane is in.
///
/// Kept free of tmux/process/fs I/O specifically so it can be exercised by
/// snapshot fixtures — see the `tests` module. Add a new captured pane dump
/// under `tests/fixtures/` and it's covered here with no mocking.
fn classify_activity(
    content: &str,
    capture_escaped: impl FnOnce() -> Option<String>,
) -> ActivityResult {
    // Look at the last portion for various indicators
    // Filter empty lines first, then take last 15 non-empty lines
    let last_portion: String = content
        .lines()
        .rev()
        .filter(|l| !l.trim().is_empty())
        .take(15)
        .collect::<Vec<_>>()
        .join("\n");

    // Hitting the session/usage limit renders as a result row
    // "⎿  You've hit your session limit · resets ..." usually followed by the
    // /rate-limit-options selector ("❯ 1. Stop and wait for limit to reset").
    // That selector would be claimed by the Question branch below — but this
    // isn't a question in any meaningful sense: no answer I pick unblocks the
    // session before the reset clock does. So it gets its own state, checked
    // before everything else. Anchored the same way as the API-error chrome:
    // trimmed line STARTS with "⎿" with the limit text as its immediate body,
    // so narration that merely QUOTES the chrome doesn't fire.
    let limit_pattern = Regex::new(r"(?m)^\s*⎿\s+You['’]ve hit your session limit").unwrap();
    if limit_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Limit, draft_content: None, question_content: None };
    }

    // Check for question state FIRST: a blocking selection prompt is the
    // highest-priority signal — it means Claude has stopped and is waiting on me,
    // and it must win over leftover spinner text or active todos. Two distinct
    // renderings both mean "waiting for me to pick an option":
    //   1. Permission/selector menu: "❯ 1. Option text" (the ❯ marks the cursor)
    //   2. AskUserQuestion widget: a boxed question whose footer reads
    //      "Enter to select · ↑/↓ to navigate". This footer is unique to the
    //      widget — normal output never prints it — so it's the reliable marker.
    // The widget can be tall, so we match against the full capture, not just the
    // last 15 lines (the question header may have scrolled above last_portion).
    // The live AskUserQuestion footer is left-aligned widget chrome: trimmed, the
    // line STARTS with "Enter to select". Anchoring on the start (not a substring
    // match) rejects scrollback that merely quotes the footer mid-line — e.g. a
    // session debugging this very script, or one that captured another's pane,
    // where the text is always preceded by line numbers, prose, or code.
    // Typed text in the live input box, if any. The box always renders its mode
    // footer ("⏵⏵ … (shift+tab to cycle)"); real selectors (permission /
    // AskUserQuestion / limit) carry their own footer instead, never this one. So
    // a "❯ 1. …" line under this footer is the user typing a numbered list — NOT
    // a selector — and must suppress the question branch below.
    // Search `content` (top-down order), NOT `last_portion`: last_portion is
    // built bottom-up, so input_box_text's own rev() would cancel out and pick
    // the TOPMOST ">"-looking line — e.g. quoted npm output ("> playwright …")
    // in a tool result — instead of the live input box at the bottom.
    let typed_input = last_portion
        .contains("shift+tab to cycle")
        .then(|| input_box_text(content))
        .flatten();

    let question_selector_pattern = Regex::new(r"(?m)^\s*❯\s*\d+\.\s+.+$").unwrap();
    let is_selector = question_selector_pattern.is_match(&last_portion);
    let is_askquestion = last_portion
        .lines()
        .any(|l| l.trim_start().starts_with("Enter to select") && l.contains("↑/↓ to navigate"));
    if (is_selector || is_askquestion) && typed_input.is_none() {
        // Extract the question text - the nearest line ending with "?" searching
        // upward from the bottom (skip prompt lines and option rows).
        let question_text = content
            .lines()
            .rev()
            .take(30)
            .find(|line| {
                let trimmed = line.trim();
                trimmed.ends_with('?') && !trimmed.starts_with('>') && !trimmed.contains('❯')
            })
            .map(|s| {
                let trimmed = s.trim().to_string();
                if trimmed.len() > 60 {
                    format!("{}...", &trimmed[..60])
                } else {
                    trimmed
                }
            });

        return ActivityResult {
            state: ClaudeState::Question,
            draft_content: None,
            question_content: question_text,
        };
    }

    // Match spinner pattern: a status phrase ending in the ellipsis glyph "…".
    // Single-word labels render as "Running…", "Cogitating…" — but Claude Code
    // also emits MULTI-WORD labels whose "…" trails a lowercase tail word, e.g.
    // "Building and verifying static musl binary…", "Baking the response…". The
    // old `[A-Z][a-z]+…` required the capitalized word to sit IMMEDIATELY before
    // "…", so every multi-word spinner was misread as Finished — an active
    // session looking idle. But bare "<letters>…" is TOO loose the other way:
    // the welcome box truncates long model names ("claude-fable-5 with high
    // effo… ·"), reading an idle session as Active forever. The timer suffix
    // disambiguates — a live spinner always renders "… (<elapsed>…", truncated
    // prose never grows a paren — so we require it. The word before "…" can end
    // in a digit too ("Wiring Postgres backups to R2…"), hence \p{N}.
    // A live spinner is unambiguous: Claude is working THIS frame. We do NOT gate
    // it on has_prompt_at_end — the TUI always renders its input box ("❯ ") at the
    // bottom of the pane even while the spinner runs above it, so that guard would
    // veto Active on essentially every frame. The genuine "stopped, waiting on me"
    // cases (selector / AskUserQuestion) are matched earlier and already returned.
    // Anchored to a line-leading spinner glyph: sessions QUOTE spinner lines in
    // prose (e.g. a recap discussing "…R2… (3m 56s…"), and an unanchored match
    // read those idle panes as Active. Real spinners always render as their own
    // line — glyph, space, phrase, "… (<elapsed>" — while quoted ones sit mid-line
    // or behind list/chrome prefixes ("- ", "⎿  "). [^…]* keeps the match inside
    // one spinner phrase so a lazy dot can't bridge from a literal "…" in prose to
    // a later "… (". If the glyph alphabet ever grows past this set, the
    // transcript override in get_claude_windows still catches the missed Active.
    let spinner_pattern = Regex::new(r"(?m)^\s*[·✢✳✶✻✽∗*]\s+[^…]*[\p{L}\p{N}]… \(").unwrap();

    if spinner_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Active, draft_content: None, question_content: None };
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
            question_content: None,
        };
    }

    // Check for draft state: user has typed something after "> "
    // The bypass permissions prompt is visible and there's actual text after "> "
    // Note: We need to distinguish real input from grey suggestions (dim text)
    // This must come BEFORE the fresh session check, as user may type on welcome screen
    if last_portion.contains("bypass permissions") {
        // Re-capture with escape codes to detect dim text (suggestions)
        if let Some(content_esc) = capture_escaped() {
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
                            question_content: None,
                        };
                    }
                }
            }
        }
    }

    // User-aborted turn: esc mid-tool-call renders result-row chrome
    // "⎿  Interrupted · What should Claude do instead?" and drops back to a live
    // prompt — same shape as the API-error row, same anchoring. Must precede
    // BOTH the fresh-session check (a `claude -c` continuation still shows the
    // welcome box, which reads as Empty on full-content match) and the
    // prompt-line gate (Finished would bury it — and todos usually still have
    // pending items here, so the Finished→Active upgrade in get_claude_windows
    // would then mislabel the session as working).
    let interrupted_pattern = Regex::new(r"(?m)^\s*⎿\s+Interrupted").unwrap();
    if interrupted_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Interrupted, draft_content: None, question_content: None };
    }

    // API errors render as Claude Code's own tool-result chrome: a result row
    // led by the "⎿" glyph whose body is "API Error: <code> <reason>" (e.g.
    // "⎿  API Error: 529 Overloaded.", "⎿  API Error: Connection error.").
    // Unlike usage-limit wedges, these abort the turn and DROP BACK to a live
    // prompt — so this MUST be checked before the prompt-line gate below, which
    // would otherwise mis-read the idle "❯ " as Finished and bury the failure.
    //
    // Two guards keep this from firing on Claude's own narration that QUOTES the
    // chrome (e.g. a session — like this one — discussing an API error it saw):
    //   1. A live spinner already returned Active above, so a working session
    //      that mentions the error never reaches here.
    //   2. The row must be GENUINE chrome, not quoted: the line, once trimmed,
    //      STARTS with "⎿" and "API Error:" is its IMMEDIATE body — only
    //      whitespace between them. Quoted narration nests a second glyph
    //      ("⎿  ⎿  API Error:") or wraps it in prose, so "API Error:" is not the
    //      row's own first token and the anchored match rejects it.
    let api_error_pattern = Regex::new(r"(?m)^\s*⎿\s+API Error:").unwrap();
    if api_error_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Error, draft_content: None, question_content: None };
    }


    // User has typed into the input box but not sent yet. We don't distinguish
    // empty/finished/input precisely (see README) — a non-empty input line under
    // the mode footer is enough. Comes after the spinner/draft/error branches so
    // a genuinely working or errored session still wins — but BEFORE the fresh
    // welcome check: typing on the welcome screen is input, not an empty pane.
    if typed_input.is_some() {
        return ActivityResult { state: ClaudeState::Input, draft_content: None, question_content: None };
    }

    // Check for fresh session (welcome screen) - after the draft/typed branches.
    // v2.1.15x dropped the old standalone "Tips for getting started"/"No recent
    // activity" text in favor of the banner logo, but the "Welcome back" box of
    // a RELAUNCHED claude still carries the "Tips" string. Every marker is gated
    // on the absence of conversation bullets ("●"): a relaunch/resume paints its
    // welcome UNDER the previous session's rows, and a pane that still shows a
    // conversation is that conversation's state (usually Finished via the prompt
    // gate below), not an empty one.
    if !content.contains('●')
        && (content.contains("▐▛███▜▌")
            || content.contains("No recent activity")
            || content.contains("Tips for getting started"))
    {
        return ActivityResult { state: ClaudeState::Empty, draft_content: None, question_content: None };
    }

    // A dead claude: on exit the TUI prints "Resume this session with:" and the
    // bare `claude --resume <uuid>` command, then hands the pane back to the
    // shell. The conversation is over — Finished. Restricted to the recent tail:
    // an exit hint deep in scrollback under a RELAUNCHED claude must not shadow
    // the live session's state.
    if dead_claude_resume_id(&last_portion).is_some() {
        return ActivityResult { state: ClaudeState::Finished, draft_content: None, question_content: None };
    }

    // Check if there's an input prompt line - indicates Claude is waiting for
    // input (task done). Modern Claude Code renders the prompt as "❯ "; older
    // builds used "> ". Either one means Finished.
    let has_prompt = content.lines().any(is_prompt_line);
    if has_prompt {
        return ActivityResult { state: ClaudeState::Finished, draft_content: None, question_content: None };
    }

    // Error state is reserved for Claude actually being WEDGED — chiefly running
    // out of the usage allowance. We get here only when no prompt line was
    // captured (a live prompt always means Finished, even if earlier output
    // mentioned an error). The pattern is intentionally narrow: it matches the
    // verbatim strings Claude Code prints when blocked on limits, NOT prose that
    // happens to contain the word "error" — Claude narrating a build failure in
    // its recap ("Error: No repository field…") is a finished, healthy session,
    // not an errored one.
    let error_pattern =
        Regex::new(r"(?i)(usage limit reached|approaching usage limit|5-hour limit|rate limit exceeded|too many requests)")
            .unwrap();

    if error_pattern.is_match(&last_portion) {
        return ActivityResult { state: ClaudeState::Error, draft_content: None, question_content: None };
    }

    ActivityResult { state: ClaudeState::Finished, draft_content: None, question_content: None }
}

// ----- 5-hour usage % from Claude Code's OAuth-authenticated /api/oauth/usage -----

#[derive(Default, Clone, Copy, Serialize, Deserialize)]
struct UsageInfo {
    /// Percent of 5h limit used [0, 100]. None = unknown.
    five_hour_used_pct: Option<f64>,
    /// Unix epoch seconds at which the 5h window resets. None = unknown.
    five_hour_resets_at: Option<i64>,
}

#[derive(Default, Serialize, Deserialize)]
struct CacheState {
    /// "session:window_index" -> state name (as_str)
    window_states: HashMap<String, String>,
    usage: UsageInfo,
    /// Unix epoch of last fetch attempt (success or fail). Throttles retries
    /// so we don't hammer the endpoint when it's per-minute rate-limited.
    last_fetch_attempt_at: Option<i64>,
}

#[derive(Deserialize)]
struct ClaudeCreds {
    #[serde(rename = "claudeAiOauth")]
    claude_ai_oauth: ClaudeOauth,
}

#[derive(Deserialize)]
struct ClaudeOauth {
    #[serde(rename = "accessToken")]
    access_token: String,
}

fn cache_path() -> Option<PathBuf> {
    std::env::var("HOME")
        .ok()
        .map(|h| PathBuf::from(h).join(".cache/claude-sessions-state.json"))
}

fn load_cache() -> CacheState {
    let Some(p) = cache_path() else { return CacheState::default() };
    let Ok(s) = fs::read_to_string(&p) else { return CacheState::default() };
    serde_json::from_str(&s).unwrap_or_default()
}

fn save_cache(cache: &CacheState) {
    let Some(p) = cache_path() else { return };
    if let Some(parent) = p.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(s) = serde_json::to_string(cache) {
        let _ = fs::write(&p, s);
    }
}

/// Fetch 5h utilization from Claude Code's unified rate-limit headers, read off a
/// minimal inference call.
///
/// The old GET /api/oauth/usage path is dead: as of the inference-only OAuth
/// token (scopes = ["user:inference"]) it hard-returns 429 rate_limit_error
/// regardless of CLI-style headers. The live signal now rides on the
/// `anthropic-ratelimit-unified-5h-*` response headers that come back on every
/// POST /v1/messages — so we make the cheapest possible call (haiku, max_tokens:1)
/// and read the headers, discarding the body.
/// ponytail: costs ~1 token per fetch; FETCH_THROTTLE_SECS keeps it to ≤1/min.
/// Returns None on any failure so the caller falls back to cached usage.
fn fetch_usage() -> Option<UsageInfo> {
    let home = std::env::var("HOME").ok()?;
    let creds_raw = fs::read_to_string(PathBuf::from(home).join(".claude/.credentials.json")).ok()?;
    let creds: ClaudeCreds = serde_json::from_str(&creds_raw).ok()?;

    // -D - dumps response headers to stdout; -o /dev/null drops the body.
    let output = Command::new("curl")
        .args([
            "-s", "-D", "-", "-o", "/dev/null",
            "-X", "POST",
            "-H", &format!("Authorization: Bearer {}", creds.claude_ai_oauth.access_token),
            "-H", "anthropic-beta: oauth-2025-04-20",
            "-H", "anthropic-version: 2023-06-01",
            "-H", "User-Agent: claude-cli/1.0.119 (external, cli)",
            "-H", "x-app: cli",
            "-H", "content-type: application/json",
            "-d", r#"{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}"#,
            "https://api.anthropic.com/v1/messages",
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let headers = String::from_utf8_lossy(&output.stdout);
    let mut util: Option<f64> = None;
    let mut reset: Option<i64> = None;
    for line in headers.lines() {
        let Some((k, v)) = line.split_once(':') else { continue };
        match k.trim().to_ascii_lowercase().as_str() {
            "anthropic-ratelimit-unified-5h-utilization" => util = v.trim().parse().ok(),
            "anthropic-ratelimit-unified-5h-reset" => reset = v.trim().parse().ok(),
            _ => {}
        }
    }

    // utilization here is a 0..1 fraction (the old endpoint reported 0..100).
    Some(UsageInfo {
        five_hour_used_pct: Some(util? * 100.0),
        five_hour_resets_at: reset,
    })
}

fn now_epoch() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn format_duration_until(target: i64) -> String {
    let remaining = target - now_epoch();
    if remaining <= 0 {
        return "?".to_string();
    }
    let hours = remaining / 3600;
    let mins = (remaining % 3600) / 60;
    if hours > 0 {
        format!("{}h{:02}m", hours, mins)
    } else {
        format!("{}m", mins)
    }
}

fn format_usage_header(u: &UsageInfo) -> String {
    // If we know when the window resets and that moment has passed, the window
    // has rolled over without us refetching — assume the allocation is fresh
    // (100% left) and drop the countdown entirely.
    if let Some(reset) = u.five_hour_resets_at {
        if now_epoch() >= reset {
            return "100%".to_string();
        }
    }

    let pct_left = match u.five_hour_used_pct {
        Some(used) => format!("{:.0}%", (100.0 - used).max(0.0)),
        None => "?".to_string(),
    };
    let time_left = match u.five_hour_resets_at {
        Some(t) => format_duration_until(t),
        None => "?".to_string(),
    };
    format!("{time_left} · {pct_left}")
}

fn current_state_map(windows: &[ClaudeWindow]) -> HashMap<String, String> {
    windows
        .iter()
        .map(|w| (format!("{}:{}", w.session, w.window_index), w.state.as_str().to_string()))
        .collect()
}

/// Minimum seconds between fetch attempts. The /api/oauth/usage endpoint
/// applies a sticky per-token rate-limit; this throttle prevents storming it.
const FETCH_THROTTLE_SECS: i64 = 60;

/// Refetch when:
/// - no prior state to compare against, or
/// - cached usage is unknown (never fetched successfully), or
/// - cached resets_at is unknown or has elapsed, or
/// - a window just transitioned INTO active/finished/question.
/// Always gated by FETCH_THROTTLE_SECS since last attempt.
fn should_recompute(prev: &CacheState, windows: &[ClaudeWindow]) -> bool {
    // Throttle: respect minimum gap between attempts (success OR failure)
    if let Some(last) = prev.last_fetch_attempt_at {
        if now_epoch() - last < FETCH_THROTTLE_SECS {
            return false;
        }
    }

    if prev.window_states.is_empty() {
        return true;
    }
    if prev.usage.five_hour_used_pct.is_none() {
        return true;
    }
    match prev.usage.five_hour_resets_at {
        None => return true, // never got a successful fetch
        Some(reset) if now_epoch() >= reset => return true, // window elapsed
        _ => {}
    }
    for w in windows {
        let key = format!("{}:{}", w.session, w.window_index);
        let new_state = w.state.as_str();
        let old_state = prev.window_states.get(&key).map(|s| s.as_str()).unwrap_or("");
        if old_state != new_state
            && matches!(
                w.state,
                ClaudeState::Active | ClaudeState::Finished | ClaudeState::Question
            )
        {
            return true;
        }
    }
    false
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

    // Find sessions that have at least one real session slot: a non-empty
    // window OR a live (if fresh) claude. Used below to hide shell-only
    // claude-named windows in sessions where actual claudes exist.
    let sessions_with_non_empty: HashSet<String> = session_windows
        .iter()
        .filter(|(_, wins)| {
            wins.iter()
                .any(|w| w.state != ClaudeState::Empty || w.claude_running)
        })
        .map(|(session, _)| session.clone())
        .collect();

    // Collect results. Empty DEDUP applies only to claude-named windows sitting
    // at a shell — a live claude on its welcome screen is a real session the
    // user opened and must always be shown ("skip empty" used to swallow it):
    //   - shell windows in sessions that have real claudes are hidden entirely
    //   - all-shell sessions collapse to a single empty row
    let mut results: Vec<&ClaudeWindow> = Vec::new();
    let mut seen_empty_session: HashSet<&str> = HashSet::new();

    for window in &windows {
        if window.state == ClaudeState::Empty && !window.claude_running {
            if sessions_with_non_empty.contains(&window.session) {
                continue;
            }
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
    let mut sessions = Sessions::new(args.compact, args.markup);
    for window in results {
        sessions.add(SessionEntry {
            name: window.session.clone(),
            window_index: window.window_index,
            state: window.state,
            active_todo: window.active_todo.clone(),
            draft_content: window.draft_content.clone(),
            question_content: window.question_content.clone(),
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

    // Refetch 5h utilization on state flip, on cache time-staleness,
    // or when prior usage is unknown. Throttled. Otherwise reuse cache.
    let cache = load_cache();
    let did_attempt = should_recompute(&cache, &windows);
    let usage = if did_attempt {
        fetch_usage().unwrap_or(cache.usage)
    } else {
        cache.usage
    };
    save_cache(&CacheState {
        window_states: current_state_map(&windows),
        usage,
        last_fetch_attempt_at: if did_attempt {
            Some(now_epoch())
        } else {
            cache.last_fetch_attempt_at
        },
    });

    if args.json {
        println!("{}", serde_json::to_string(&sessions.entries).unwrap());
    } else if args.markup {
        // Header is purely informational; left uncolored so it inherits the
        // widget's default text color (the eww label's own styling).
        println!("{}", pango_escape(&format_usage_header(&usage)));
        println!("{}", sessions);
    } else {
        println!("{}", format_usage_header(&usage).dimmed());
        println!("{}", sessions);
    }
}

#[cfg(test)]
mod tests {
    //! Snapshot tests for the terminal-state classifier.
    //!
    //! Every regression this script has ever had lived in `classify_activity`:
    //! a real pane that got read as the wrong `ClaudeState`. These tests pin that
    //! function against REAL captured pane dumps — no tmux, no /proc, no mocks.
    //!
    //! ## Fixture layout (`tests/fixtures/`)
    //! - `<state>__<name>.txt`  — plain `tmux capture-pane -p` output. The
    //!   `<state>` prefix (before `__`) is the EXPECTED state and is asserted.
    //! - `<state>__<name>.esc`  — OPTIONAL companion: escape-coded
    //!   `tmux capture-pane -p -e` output. Only the draft path consults it; if
    //!   absent the classifier is told the escaped capture is unavailable.
    //! - `<state>__<name>.jsonl` — OPTIONAL companion: tail of the session's
    //!   transcript. States now come from pane text AND the transcript (the
    //!   active↔finished deliberation), so fixtures for that path persist both.
    //!   The prefix names the FINAL state after `refine_finished`, letting one
    //!   pane dump pin both verdicts (same .txt, different .jsonl).
    //!
    //! ## Adding a case (the whole point — trivial, no code edit)
    //! Capture a live pane in the state you want to lock in:
    //!     tmux capture-pane -t <sess>:<win> -p -S -50   > tests/fixtures/question__askwidget.txt
    //!     # only for draft cases, also grab the escaped capture:
    //!     tmux capture-pane -t <sess>:<win> -p -e -S -10 > tests/fixtures/draft__typed.esc
    //!     # for active/finished deliberation cases, persist the transcript tail:
    //!     tail -n 15 ~/.claude/projects/<proj>/<session>.jsonl > tests/fixtures/finished__idle.jsonl
    //! Then `cargo insta accept` to record its full ActivityResult snapshot.
    //! The filename-prefix assertion runs automatically.

    use super::*;
    use std::fs;
    use std::path::{Path, PathBuf};

    fn fixtures_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
    }

    /// Parse the expected state out of a fixture filename's `<state>__` prefix.
    fn expected_state_from_name(stem: &str) -> ClaudeState {
        let prefix = stem.split("__").next().expect("fixture name has a prefix");
        match prefix {
            "empty" => ClaudeState::Empty,
            "active" => ClaudeState::Active,
            "finished" => ClaudeState::Finished,
            "draft" => ClaudeState::Draft,
            "question" => ClaudeState::Question,
            "input" => ClaudeState::Input,
            "error" => ClaudeState::Error,
            "limit" => ClaudeState::Limit,
            "interrupted" => ClaudeState::Interrupted,
            other => panic!(
                "fixture {stem:?} has unknown state prefix {other:?}; \
                 name it <state>__<desc>.txt"
            ),
        }
    }

    /// Walk every `*.txt` fixture, classify it, and assert two things:
    ///   1. the classified state equals the filename's `<state>__` prefix, and
    ///   2. the full ActivityResult matches its recorded insta snapshot.
    /// Drop a new correctly-named `.txt` in and it's covered with zero code edits.
    #[test]
    fn fixtures_classify_to_their_named_state() {
        let dir = fixtures_dir();
        let mut txts: Vec<PathBuf> = fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("read {dir:?}: {e}"))
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|x| x == "txt"))
            .collect();
        // Deterministic order so the snapshot review list is stable run-to-run.
        txts.sort();

        assert!(
            !txts.is_empty(),
            "no *.txt fixtures in {dir:?} — capture one with `tmux capture-pane -p`"
        );

        for txt in txts {
            let stem = txt.file_stem().unwrap().to_string_lossy().to_string();
            let plain = fs::read_to_string(&txt).unwrap_or_else(|e| panic!("read {txt:?}: {e}"));

            // Companion escaped capture, only present for draft fixtures.
            let esc = fs::read_to_string(txt.with_extension("esc")).ok();
            let result = classify_activity(&plain, || esc.clone());

            // Companion transcript tail, only present for fixtures pinning the
            // active↔finished deliberation. Replayed through the same
            // refine_finished the production Finished arm uses (todos-fallback
            // pinned to false — fixtures carry no todo files).
            let jsonl = txt.with_extension("jsonl");
            let (final_state, verdict) = if jsonl.exists() {
                assert_eq!(
                    result.state,
                    ClaudeState::Finished,
                    "fixture {stem:?} has a .jsonl companion but the pane classified as \
                     {:?} — the transcript is only consulted for Finished panes",
                    result.state
                );
                let verdict = transcript_working(&jsonl);
                (ClaudeState::refine_finished(verdict, false), verdict)
            } else {
                (result.state, None)
            };

            let expected = expected_state_from_name(&stem);
            assert_eq!(
                final_state, expected,
                "fixture {stem:?} resolved to {final_state:?} (pane: {:?}, transcript: {verdict:?}), \
                 expected {expected:?}",
                result.state
            );

            // Full-result snapshot catches subtler drift (wrong extracted
            // question text, wrong truncation) the state check alone can't see.
            // Transcript-arbitrated fixtures also pin the verdict itself.
            if jsonl.exists() {
                insta::assert_debug_snapshot!(stem.clone(), (result, verdict));
            } else {
                insta::assert_debug_snapshot!(stem.clone(), result);
            }
        }
    }
}
