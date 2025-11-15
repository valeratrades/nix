use nvim_oxi::{api, Array, Object};

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
pub fn jump_to_diagnostic(direction: i64, request_severity: String) {
    let _ = std::panic::catch_unwind(|| {
        // Get diagnostics for current buffer
        let bufnr = api::get_current_buf();
        let diagnostics = get_buffer_diagnostics(bufnr);

        if diagnostics.is_empty() {
            echo("no diagnostics in buffer".to_string(), Some("Comment".to_string()));
            return;
        }

        // Get current cursor position (0-indexed line)
        let cursor = api::get_current_win().get_cursor().unwrap_or((1, 0));
        let current_line = (cursor.0 as i64) - 1;

        // Check if we're on a diagnostic line and no popup is open
        let popups = crate::remap::get_popups();
        for diag in &diagnostics {
            if let Some(lnum) = get_diagnostic_field::<i64>(diag, "lnum") {
                if lnum == current_line && popups.is_empty() {
                    open_diagnostic_float();
                    return;
                }
            }
        }

        // Determine target severity
        let only_errors = request_severity != "all" && diagnostics.iter().any(|d| {
            get_diagnostic_field::<i64>(d, "severity").map(|s| s == 1).unwrap_or(false)
        });

        if only_errors {
            // Navigate only to errors (severity 1)
            if let Some(next_diag) = find_next_diagnostic(&diagnostics, current_line, direction, Some(1)) {
                jump_to_diagnostic_position(&next_diag);
                open_diagnostic_float();
            }
        } else {
            // Navigate to all diagnostics, skipping any on current line
            if let Some(next_diag) = find_next_diagnostic_skip_current_line(&diagnostics, current_line, direction) {
                jump_to_diagnostic_position(&next_diag);
                open_diagnostic_float();
            }
        }
    });
}

/// Get diagnostics for a buffer
fn get_buffer_diagnostics(bufnr: nvim_oxi::api::Buffer) -> Vec<nvim_oxi::Dictionary> {
    // Call vim.diagnostic.get(bufnr) - using 0 for current buffer
    match api::call_function("luaeval", ("vim.diagnostic.get(0)",)) {
        Ok(arr) => {
            let array: nvim_oxi::Array = arr;
            array.into_iter()
                .filter_map(|obj| nvim_oxi::Dictionary::try_from(obj).ok())
                .collect()
        }
        Err(_) => vec![]
    }
}

/// Get a typed field from a diagnostic dictionary
fn get_diagnostic_field<T: TryFrom<Object>>(diag: &nvim_oxi::Dictionary, field: &str) -> Option<T> {
    diag.get(field)
        .and_then(|obj| T::try_from(obj.clone()).ok())
}

/// Find next diagnostic with optional severity filter
fn find_next_diagnostic(
    diagnostics: &[nvim_oxi::Dictionary],
    current_line: i64,
    direction: i64,
    severity_filter: Option<i64>,
) -> Option<nvim_oxi::Dictionary> {
    let filtered: Vec<_> = diagnostics.iter()
        .filter(|d| {
            if let Some(sev) = severity_filter {
                get_diagnostic_field::<i64>(d, "severity").map(|s| s == sev).unwrap_or(false)
            } else {
                true
            }
        })
        .collect();

    if filtered.is_empty() {
        return None;
    }

    // Sort by line number
    let mut sorted: Vec<_> = filtered.iter().map(|d| (*d).clone()).collect();
    sorted.sort_by_key(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0));

    if direction > 0 {
        // Find next
        let first = sorted.first().cloned();
        sorted.into_iter()
            .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) > current_line)
            .or(first)
    } else {
        // Find previous
        sorted.reverse();
        let first = sorted.first().cloned();
        sorted.into_iter()
            .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) < current_line)
            .or(first)
    }
}

/// Find next diagnostic, skipping any on current line
fn find_next_diagnostic_skip_current_line(
    diagnostics: &[nvim_oxi::Dictionary],
    current_line: i64,
    direction: i64,
) -> Option<nvim_oxi::Dictionary> {
    let mut sorted: Vec<_> = diagnostics.to_vec();
    sorted.sort_by_key(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0));

    if direction > 0 {
        sorted.into_iter()
            .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) > current_line)
            .or_else(|| {
                // Wrap around to first diagnostic not on current line
                diagnostics.iter()
                    .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) != current_line)
                    .cloned()
            })
    } else {
        sorted.reverse();
        sorted.into_iter()
            .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) < current_line)
            .or_else(|| {
                // Wrap around to last diagnostic not on current line
                diagnostics.iter()
                    .rev()
                    .find(|d| get_diagnostic_field::<i64>(d, "lnum").unwrap_or(0) != current_line)
                    .cloned()
            })
    }
}

/// Jump cursor to diagnostic position
fn jump_to_diagnostic_position(diag: &nvim_oxi::Dictionary) {
    if let (Some(lnum), Some(col)) = (
        get_diagnostic_field::<i64>(diag, "lnum"),
        get_diagnostic_field::<i64>(diag, "col"),
    ) {
        let _ = api::get_current_win().set_cursor((lnum + 1) as usize, col as usize);
    }
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
