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
        if diagnostics.is_empty() {
            echo("no diagnostics in 0".to_string(), Some("Comment".to_string()));
            return;
        }

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

        // log diagnostics state
        {
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
        }


        // Get current line (1-indexed)
        let current_line: i64 = api::call_function("line", (".",)).unwrap_or(1);

        /// Check if a popup is currently open
        let popup_open = {
            let popups = crate::remap::get_popups();
            !popups.is_empty()
        };

        // Check if we're casually on a diagnostic line (without popup open)
        let on_diagnostic_line = interpreted_diags.iter().any(|d| d.start.0 == current_line);
        if on_diagnostic_line && !popup_open {
            // meaning we selected casually
            open_diagnostic_float();
            return;
        }

        // Check if we should navigate exclusively between errors
        let has_errors = diagnostics.iter().any(|d| {
            let severity: Option<i64> = get_diagnostic_field(d, "severity");
            severity == Some(1)
        });
        let filter_errors_only = has_errors && request_severity != "all";

        // Filter diagnostics for navigation (errors-only if needed)
        let nav_diags: Vec<&InterpretedDiagnostic> = if filter_errors_only {
            // TODO: We need severity in InterpretedDiagnostic to filter properly
            // For now, use old behavior
            let go_action = if direction == 1 { "goto_next" } else { "goto_prev" };
            let lua_code = format!(
                r#"vim.diagnostic.{}({{ float = {{ format = function(diagnostic) return vim.split(diagnostic.message, "\n")[1] end, focusable = true, header = "" }}, severity = {{ 1 }} }})"#,
                go_action
            );
            let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
            return;
        } else {
            interpreted_diags.iter().collect()
        };

        // Get all unique lines with diagnostics
        use std::collections::HashSet;
        let mut lines_with_diags: Vec<i64> = nav_diags.iter()
            .map(|d| d.start.0)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        lines_with_diags.sort_unstable();

        // Find next/prev line to jump to
        let target_line = if direction == 1 {
            // Next: find first line > current_line, or wrap to first
            lines_with_diags.iter()
                .find(|&&l| l > current_line)
                .copied()
                .unwrap_or(*lines_with_diags.first().unwrap_or(&current_line))
        } else {
            // Prev: find last line < current_line, or wrap to last
            lines_with_diags.iter()
                .rev()
                .find(|&&l| l < current_line)
                .copied()
                .unwrap_or(*lines_with_diags.last().unwrap_or(&current_line))
        };

        // Get all diagnostics on the target line, sorted by column
        let mut diags_on_target: Vec<&InterpretedDiagnostic> = interpreted_diags.iter()
            .filter(|d| d.start.0 == target_line)
            .collect();
        diags_on_target.sort_by_key(|d| d.start.1);

        if let Some(last_diag) = diags_on_target.last() {
            // Jump to the last diagnostic on the target line
            let _ = api::call_function::<_, ()>("nvim_win_set_cursor", (0, Array::from_iter(vec![
                Object::from(last_diag.start.0),
                Object::from(last_diag.start.1)
            ])));

            debug_log(format!("\n=== OPENING FLOAT ===\nJumped to line {}, {} diagnostics on line",
                target_line, diags_on_target.len()));

            // Defer popup opening after cursor has moved
            crate::utils::defer_fn(1, || {
                open_diagnostic_float();
            });
        }
        return;
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
