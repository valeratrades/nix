use nvim_oxi::{api, Array, Object};
use std::fs::OpenOptions;
use std::io::Write;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
struct DiagnosticRange {
    start: DiagnosticPosition,
    end: DiagnosticPosition,
}

#[derive(Debug, Serialize, Deserialize)]
struct DiagnosticPosition {
    line: i64,
    character: i64,
}

#[derive(Debug, Serialize, Deserialize)]
struct LspData {
    range: DiagnosticRange,
    source: Option<String>,
    code: Option<String>,
    message: String,
    severity: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
struct UserData {
    lsp: Option<LspData>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Diagnostic {
    lnum: i64,
    bufnr: i64,
    col: i64,
    end_lnum: i64,
    end_col: i64,
    severity: i64,
    message: String,
    source: Option<String>,
    code: Option<String>,
    namespace: Option<i64>,
    user_data: Option<UserData>,
}

#[derive(Debug)]
struct InterpretedDiagnostic {
    code: Option<String>,
    message: String,
    /// NB: (line, col) where line is 1-indexed
    start: (i64, i64),
    /// NB: (line, col) where line is 1-indexed
    end: (i64, i64),
}

impl From<Diagnostic> for InterpretedDiagnostic {
    fn from(diag: Diagnostic) -> Self {
        // Get LSP range if available, otherwise use lnum/col
        let (start, end) = if let Some(lsp_range) = diag.user_data
            .as_ref()
            .and_then(|u| u.lsp.as_ref())
            .map(|l| &l.range)
        {
            // LSP range is 0-indexed, convert to 1-indexed
            (
                (lsp_range.start.line + 1, lsp_range.start.character),
                (lsp_range.end.line + 1, lsp_range.end.character),
            )
        } else {
            // lnum is 0-indexed, convert to 1-indexed
            (
                (diag.lnum + 1, diag.col),
                (diag.end_lnum + 1, diag.end_col),
            )
        };

        InterpretedDiagnostic {
            code: diag.code,
            message: diag.message,
            start,
            end,
        }
    }
}

/// Echo a message with a highlight type
pub fn echo(text: String, hl_type: Option<String>) {
    let hl = hl_type.unwrap_or_else(|| "Comment".to_string());

    // Capitalize first letter if needed
    let hl_capitalized = if let Some(first_char) = hl.chars().next() {
        if first_char.is_lowercase() {
            let mut chars = hl.chars();
            chars.next();
            format!("{}{}", first_char.to_uppercase(), chars.as_str())
        } else {
            hl
        }
    } else {
        hl
    };

    // Original Lua: vim.api.nvim_echo({{ text, hl }}, false, {})
    let chunks = Array::from_iter(vec![
        Object::from(Array::from_iter(vec![
            Object::from(text),
            Object::from(hl_capitalized),
        ]))
    ]);
    let _ = api::call_function::<_, ()>("nvim_echo", (chunks, false, Array::new()));
}

/// Jump to diagnostic in the given direction
/// direction: 1 for next, -1 for prev
/// request_severity: "all" to include all severities, otherwise only errors
// Module-level debug logging helper
fn debug_log(msg: String) {
    let log_path_tilde = "~/.local/state/nvim/rust_plugins/jump_to_diagnostic.log";
    let log_path: String = api::call_function("expand", (log_path_tilde,)).unwrap_or_else(|_| log_path_tilde.to_string());

    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .unwrap();
    writeln!(file, "{}", msg).unwrap();
}

pub fn jump_to_diagnostic(direction: i64, request_severity: String) {
    let _ = std::panic::catch_unwind(|| {
        // Setup log file - expand ~ and create directory
        let log_path_tilde = "~/.local/state/nvim/rust_plugins/jump_to_diagnostic.log";
        let log_path: String = api::call_function("expand", (log_path_tilde,)).unwrap_or_else(|_| log_path_tilde.to_string());

        // Create parent directory if needed
        if let Some(parent) = std::path::Path::new(&log_path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        // Append separator between entries
        {
            let mut file = OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(&log_path)
                .unwrap();
            writeln!(file, "\n\n======").unwrap();
        }

        // Log cursor position
        let cursor_line: i64 = api::call_function("line", (".",)).unwrap_or(0);
        let cursor_col: i64 = api::call_function("col", (".",)).unwrap_or(0);
        debug_log(format!("Cursor position: line={}, col={}", cursor_line, cursor_col));

        let bufnr = api::get_current_buf();
        let bufnr_handle = bufnr.handle();
        let diagnostics = get_buffer_diagnostics(bufnr);

        debug_log(format!("\n=== DIAGNOSTICS ({} total) ===", diagnostics.len()));

        // Get file line count and last line length
        let line_count: i64 = api::call_function("line", ("$",)).unwrap_or(1);
        let last_line_col: i64 = {
            // Get the actual text of the last line and measure its length
            let lua_code = format!("vim.fn.strlen(vim.fn.getline({}))", line_count);
            api::call_function("luaeval", (lua_code,)).unwrap_or(0)
        };
        debug_log(format!("File has {} lines, last line ends at col {}", line_count, last_line_col));

        // Parse and interpret all diagnostics first
        let mut interpreted_diags: Vec<InterpretedDiagnostic> = Vec::new();
        for i in 0..diagnostics.len() {
            let lua_code = format!("vim.fn.json_encode(vim.diagnostic.get({})[{}])", bufnr_handle, i);
            if let Ok(json_str) = api::call_function::<_, String>("luaeval", (lua_code,)) {
                if let Ok(mut diag) = serde_json::from_str::<Diagnostic>(&json_str) {
                    let mut interpreted = InterpretedDiagnostic::from(diag);

                    // Clamp diagnostic positions to file boundaries
                    if interpreted.start.0 > line_count {
                        debug_log(format!("Clamping diagnostic start from ({}, {}) to ({}, {})",
                            interpreted.start.0, interpreted.start.1, line_count, last_line_col));
                        interpreted.start = (line_count, last_line_col);
                    }
                    if interpreted.end.0 > line_count {
                        debug_log(format!("Clamping diagnostic end from ({}, {}) to ({}, {})",
                            interpreted.end.0, interpreted.end.1, line_count, last_line_col));
                        interpreted.end = (line_count, last_line_col);
                    }

                    interpreted_diags.push(interpreted);
                }
            }
        }

        // Group by line (1-indexed now)
        use std::collections::HashMap;
        let mut by_line: HashMap<i64, Vec<&InterpretedDiagnostic>> = HashMap::new();
        for diag in &interpreted_diags {
            by_line.entry(diag.start.0).or_insert_with(Vec::new).push(diag);
        }

        // Sort lines and display
        let mut lines: Vec<_> = by_line.keys().copied().collect();
        lines.sort_unstable();

        for line_num in lines {
            let diags_on_line = &by_line[&line_num];
            debug_log(format!("\n--- Line {} ({} diagnostics) ---", line_num, diags_on_line.len()));

            for diag in diags_on_line {
                debug_log(format!("  start: {:?}\n  end: {:?}\n  code: {:?}\n  message: {}\n",
                    diag.start, diag.end, diag.code, diag.message));
            }
        }
        debug_log("-----------------------------------------------------------------".to_string());

        if diagnostics.is_empty() {
            echo("no diagnostics in 0".to_string(), Some("Comment".to_string()));
            return;
        }

        // Get current line (0-indexed)
        let line: i64 = api::call_function("line", (".",)).unwrap_or(1);
        let line = line - 1;

        // severity is [1:4], the lower the "worse"
        let all_severity = vec![1, 2, 3, 4];
        let mut target_severity = all_severity.clone();

        // Check if we're on a diagnostic line and popup is not open
        let popup_open = bool_popup_open();

        for d in &diagnostics {
            let lnum: Option<i64> = get_diagnostic_field(d, "lnum");
            if lnum == Some(line) && !popup_open {
                // meaning we selected casually
                open_diagnostic_float();
                return;
            }

            // navigate exclusively between errors, if there are any
            let severity: Option<i64> = get_diagnostic_field(d, "severity");
            if severity == Some(1) && request_severity != "all" {
                target_severity = vec![1];
            }
        }

        let go_action = if direction == 1 { "goto_next" } else { "goto_prev" };
        let get_action = if direction == 1 { "get_next" } else { "get_prev" };

        if target_severity != all_severity {
            // Use goto_next/goto_prev with float option - this handles everything
            let lua_code = format!(
                r#"vim.diagnostic.{}({{ float = {{ format = function(diagnostic) return vim.split(diagnostic.message, "\n")[1] end, focusable = true, header = "" }}, severity = {{ {} }} }})"#,
                go_action,
                target_severity.iter().map(|s| s.to_string()).collect::<Vec<_>>().join(", ")
            );
            let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
            return;
        } else {
            // jump over all on current line
            let mut next_on_another_line = false;
            while !next_on_another_line {
                // Get next diagnostic using get_next/get_prev
                let lua_code = format!(
                    r#"vim.diagnostic.{}({{ severity = {{ 1, 2, 3, 4 }} }})"#,
                    get_action
                );
                let d: nvim_oxi::Dictionary = match api::call_function("luaeval", (lua_code,)) {
                    Ok(d) => d,
                    Err(_) => return,
                };

                let lnum: i64 = get_diagnostic_field(&d, "lnum").unwrap_or(0);
                let col: i64 = get_diagnostic_field(&d, "col").unwrap_or(0);

                // Set cursor position
                let _ = api::call_function::<_, ()>("nvim_win_set_cursor", (0, Array::from_iter(vec![
                    Object::from(lnum + 1),
                    Object::from(col)
                ])));

                if lnum != line {
                    next_on_another_line = true;
                    break;
                }

                if diagnostics.len() == 1 {
                    return;
                }
            }

            // Log diagnostics at cursor before opening float
            let current_line: i64 = api::call_function("line", (".",)).unwrap_or(0) - 1;
            let current_col: i64 = api::call_function("col", (".",)).unwrap_or(0);
            let diags_at_cursor: Vec<String> = diagnostics.iter()
                .filter_map(|d| {
                    let lnum: Option<i64> = get_diagnostic_field(d, "lnum");
                    let col: Option<i64> = get_diagnostic_field(d, "col");
                    if lnum == Some(current_line) {
                        let msg: Option<String> = d.get("message")
                            .and_then(|obj| nvim_oxi::String::try_from(obj.clone()).ok())
                            .map(|s| s.to_string_lossy().to_string());
                        let code: Option<String> = d.get("code")
                            .and_then(|obj| nvim_oxi::String::try_from(obj.clone()).ok())
                            .map(|s| s.to_string_lossy().to_string());
                        Some(format!("  col={}, code={:?}, msg={}", col.unwrap_or(-1), code, msg.unwrap_or_default()))
                    } else {
                        None
                    }
                })
                .collect();
            debug_log(format!("\n=== OPENING FLOAT ===\nDiagnostics on line {}:\n{}", current_line + 1, diags_at_cursor.join("\n")));

            // Defer popup opening after cursor has moved
            crate::utils::defer_fn(1, || {
                open_diagnostic_float();
            });
            return;
        }
    });
}

/// Get diagnostics for a buffer
fn get_buffer_diagnostics(bufnr: nvim_oxi::api::Buffer) -> Vec<nvim_oxi::Dictionary> {
    // Use luaeval to call vim.diagnostic.get
    let lua_code = format!("vim.diagnostic.get({})", bufnr.handle());
    match api::call_function("luaeval", (lua_code,)) {
        Ok(arr) => {
            let array: nvim_oxi::Array = arr;
            array.into_iter()
                .filter_map(|obj| nvim_oxi::Dictionary::try_from(obj).ok())
                .collect()
        }
        Err(e) => {
            echo(format!("Error getting diagnostics: {}", e), Some("ErrorMsg".to_string()));
            vec![]
        }
    }
}

/// Get a typed field from a diagnostic dictionary
fn get_diagnostic_field<T: TryFrom<Object>>(diag: &nvim_oxi::Dictionary, field: &str) -> Option<T> {
    diag.get(field)
        .and_then(|obj| T::try_from(obj.clone()).ok())
}

/// Check if a popup is currently open
fn bool_popup_open() -> bool {
    let popups = crate::remap::get_popups();
    !popups.is_empty()
}

/// Helper to open diagnostic float with standard options
fn open_diagnostic_float() {
    // Build options dictionary
    // Note: format requires a Lua function, so we use luaeval for this call
    let lua_code = r#"vim.diagnostic.open_float({
        format = function(diagnostic)
            return vim.split(diagnostic.message, "\n")[1]
        end,
        focusable = true,
        header = ""
    })"#;
    let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
}

/// Yank the contents of the diagnostic popup to system clipboard
pub fn yank_diagnostic_popup() {
    let popups = crate::remap::get_popups();

    if popups.len() == 1 {
        let popup_id = popups[0];

        // Get buffer from window
        let bufnr: i64 = api::call_function("nvim_win_get_buf", (popup_id,))
            .unwrap_or(0);

        // Get lines from buffer
        let lines: Vec<String> = api::call_function(
            "nvim_buf_get_lines",
            (bufnr, 0, -1, false)
        ).unwrap_or_else(|_| vec![]);

        // Join lines and set to clipboard
        let content = lines.join("\n");
        let _: () = api::call_function("setreg", ("+", content)).unwrap_or(());
    }
}
