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
        let bufnr = api::get_current_buf();
        let diagnostics = get_buffer_diagnostics(bufnr);

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
