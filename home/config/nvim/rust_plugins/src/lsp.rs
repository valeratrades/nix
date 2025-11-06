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
    // Original Lua wraps everything in pcall
    let _ = std::panic::catch_unwind(|| {
        // Original Lua: local diagnostics = vim.diagnostic.get(bufnr)
        let diagnostics: Vec<nvim_oxi::Dictionary> = api::call_function(
            "luaeval",
            ("vim.diagnostic.get(0)",)
        ).unwrap_or_else(|_| vec![]);

        // Original Lua: if #diagnostics == 0 then Echo("no diagnostics in 0", "Comment") end
        if diagnostics.is_empty() {
            echo("no diagnostics in 0".to_string(), Some("Comment".to_string()));
        }

        // Original Lua: local line = vim.fn.line(".") - 1
        let line: i64 = api::call_function("line", (".",))
            .unwrap_or(1);
        let line = line - 1;

        // Original Lua: local allSeverity = { 1, 2, 3, 4 }
        // Original Lua: local targetSeverity = allSeverity
        let all_severity = vec![1i64, 2, 3, 4];
        let mut target_severity = all_severity.clone();

        // Original Lua: for _, d in pairs(diagnostics) do
        let popups = crate::remap::get_popups();
        for diag in &diagnostics {
            // Original Lua: if d.lnum == line and not BoolPopupOpen() then
            if let Some(lnum_obj) = diag.get("lnum") {
                let lnum: i64 = lnum_obj.clone().try_into().unwrap_or(-1);
                if lnum == line && popups.is_empty() {
                    // Original Lua: vim.diagnostic.open_float(floatOpts); return
                    open_diagnostic_float();
                    return;
                }
            }

            // Original Lua: if d.severity == 1 and requestSeverity ~= 'all' then targetSeverity = { 1 } end
            if let Some(sev_obj) = diag.get("severity") {
                let sev: i64 = sev_obj.clone().try_into().unwrap_or(4);
                if sev == 1 && request_severity != "all" {
                    target_severity = vec![1];
                }
            }
        }

        let go_action = if direction == 1 { "goto_next" } else { "goto_prev" };
        let get_action = if direction == 1 { "get_next" } else { "get_prev" };

        // Original Lua: if targetSeverity ~= allSeverity then
        if target_severity != all_severity {
            // Original Lua: vim.diagnostic[go_action]({ float = floatOpts, severity = targetSeverity })
            let lua_code = format!(
                r#"vim.diagnostic.{}({{
                    float = {{
                        format = function(diagnostic) return vim.split(diagnostic.message, "\n")[1] end,
                        focusable = true,
                        header = ""
                    }},
                    severity = {{ 1 }}
                }})"#,
                go_action
            );
            let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
            return;
        } else {
            // Original Lua: jump over all on current line
            // local nextOnAnotherLine = false
            // while not nextOnAnotherLine do...
            let mut next_on_another_line = false;
            while !next_on_another_line {
                // Original Lua: local d = vim.diagnostic[get_action]({ severity = allSeverity })
                let lua_code = format!(
                    r#"vim.diagnostic.{}({{ severity = {{ 1, 2, 3, 4 }} }})"#,
                    get_action
                );
                let d: Option<nvim_oxi::Dictionary> = api::call_function("luaeval", (lua_code,)).ok();

                if d.is_none() {
                    break;
                }

                let d = d.unwrap();

                // Original Lua: vim.api.nvim_win_set_cursor(0, { d.lnum + 1, d.col })
                if let (Some(lnum_obj), Some(col_obj)) = (d.get("lnum"), d.get("col")) {
                    let lnum: i64 = lnum_obj.clone().try_into().unwrap_or(0);
                    let col: i64 = col_obj.clone().try_into().unwrap_or(0);
                    let _ = api::get_current_win().set_cursor((lnum + 1) as usize, col as usize);

                    // Original Lua: if d.lnum ~= line then nextOnAnotherLine = true; break end
                    if lnum != line {
                        next_on_another_line = true;
                        break;
                    }
                }

                // Original Lua: if #diagnostics == 1 then return end
                if diagnostics.len() == 1 {
                    return;
                }
            }

            // Original Lua: vim.defer_fn(function() vim.diagnostic.open_float(floatOpts) end, 1)
            crate::utils::defer_fn(1, || {
                open_diagnostic_float();
            });
        }
    });
}

/// Helper to open diagnostic float with standard options
fn open_diagnostic_float() {
    let lua_code = r#"vim.diagnostic.open_float({
        format = function(diagnostic) return vim.split(diagnostic.message, "\n")[1] end,
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
