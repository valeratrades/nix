use nvim_oxi::api;
use nvim_oxi::String as NvimString;

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

    let lua_code = format!(
        r#"vim.api.nvim_echo({{ {{ '{}', '{}' }} }}, false, {{}})"#,
        text.replace("'", "\\'"),
        hl_capitalized.replace("'", "\\'")
    );
    let _: () = api::call_function("luaeval", (lua_code,))
        .unwrap_or(());
}

/// Jump to diagnostic in the given direction
/// direction: 1 for next, -1 for prev
/// request_severity: "all" to include all severities, otherwise only errors
pub fn jump_to_diagnostic(direction: i64, request_severity: String) {
    let _ = std::panic::catch_unwind(|| {
        // Get diagnostics for current buffer
        let diagnostics: Vec<nvim_oxi::Dictionary> = api::call_function(
            "luaeval",
            ("vim.diagnostic.get(0)",)
        ).unwrap_or_else(|_| vec![]);

        if diagnostics.is_empty() {
            echo("no diagnostics in buffer".to_string(), Some("Comment".to_string()));
            return;
        }

        // Get current line (0-indexed)
        let line: i64 = api::call_function("line", (".",))
            .unwrap_or(1);
        let line = line - 1;

        // Check if we're on a line with a diagnostic and no popup is open
        let popups = crate::remap::get_popups();
        for diag in &diagnostics {
            if let Some(lnum_obj) = diag.get("lnum") {
                let lnum: i64 = lnum_obj.clone().try_into().unwrap_or(-1);
                if lnum == line && popups.is_empty() {
                    // Open float at current position
                    let lua_code = r#"
                        vim.diagnostic.open_float({
                            format = function(diagnostic)
                                return vim.split(diagnostic.message, "\n")[1]
                            end,
                            focusable = true,
                            header = ""
                        })
                    "#;
                    let _: () = api::call_function("luaeval", (lua_code,)).unwrap_or(());
                    return;
                }
            }
        }

        // Check if there are any errors (severity 1)
        let mut has_errors = false;
        for diag in &diagnostics {
            if let Some(sev_obj) = diag.get("severity") {
                let sev: i64 = sev_obj.clone().try_into().unwrap_or(4);
                if sev == 1 && request_severity != "all" {
                    has_errors = true;
                    break;
                }
            }
        }

        let go_action = if direction == 1 { "goto_next" } else { "goto_prev" };
        let get_action = if direction == 1 { "get_next" } else { "get_prev" };

        if has_errors {
            // Navigate only between errors
            let lua_code = format!(
                r#"
                vim.diagnostic.{}({{
                    float = {{
                        format = function(diagnostic)
                            return vim.split(diagnostic.message, "\n")[1]
                        end,
                        focusable = true,
                        header = ""
                    }},
                    severity = {{ 1 }}
                }})
                "#,
                go_action
            );
            let _: () = api::call_function("luaeval", (lua_code,)).unwrap_or(());
        } else {
            // Jump over all diagnostics on current line
            let lua_code = format!(
                r#"
                local line = {}
                local nextOnAnotherLine = false
                local diagnostics_count = {}
                while not nextOnAnotherLine do
                    local d = vim.diagnostic.{}({{ severity = {{ 1, 2, 3, 4 }} }})
                    if not d then break end
                    vim.api.nvim_win_set_cursor(0, {{ d.lnum + 1, d.col }})
                    if d.lnum ~= line then
                        nextOnAnotherLine = true
                        break
                    end
                    if diagnostics_count == 1 then
                        return
                    end
                end
                vim.defer_fn(function()
                    vim.diagnostic.open_float({{
                        format = function(diagnostic)
                            return vim.split(diagnostic.message, "\n")[1]
                        end,
                        focusable = true,
                        header = ""
                    }})
                end, 1)
                "#,
                line,
                diagnostics.len(),
                get_action
            );
            let _: () = api::call_function("luaeval", (lua_code,)).unwrap_or(());
        }
    });
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
