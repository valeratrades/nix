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
    // Original Lua: pcall(function() ... end)
    let lua_code = format!(
        r#"
        pcall(function()
            local bufnr = vim.api.nvim_get_current_buf()
            local diagnostics = vim.diagnostic.get(bufnr)
            if #diagnostics == 0 then
                vim.api.nvim_echo({{{{ 'no diagnostics in 0', 'Comment' }}}}, false, {{}})
            end
            local line = vim.fn.line(".") - 1
            -- severity is [1:4], the lower the "worse"
            local allSeverity = {{ 1, 2, 3, 4 }}
            local targetSeverity = allSeverity
            local floatOpts = {{
                format = function(diagnostic)
                    return vim.split(diagnostic.message, "\n")[1]
                end,
                focusable = true,
                header = ""
            }}
            local function BoolPopupOpen()
                local wins = vim.api.nvim_list_wins()
                local popups = {{}}
                for _, win_id in ipairs(wins) do
                    local config = vim.api.nvim_win_get_config(win_id)
                    if config.relative ~= "" then
                        table.insert(popups, win_id)
                    end
                end
                return #popups > 0
            end
            for _, d in pairs(diagnostics) do
                if d.lnum == line and not BoolPopupOpen() then -- meaning we selected casually
                    vim.diagnostic.open_float(floatOpts)
                    return
                end
                -- navigate exclusively between errors, if there are any
                if d.severity == 1 and "{}" ~= 'all' then
                    targetSeverity = {{ 1 }}
                end
            end

            local go_action = {} == 1 and "goto_next" or "goto_prev"
            local get_action = {} == 1 and "get_next" or "get_prev"
            if targetSeverity[1] == 1 and #targetSeverity == 1 then
                vim.diagnostic[go_action]({{ float = floatOpts, severity = targetSeverity }})
                return
            else
                -- jump over all on current line
                local nextOnAnotherLine = false
                while not nextOnAnotherLine do
                    local d = vim.diagnostic[get_action]({{ severity = allSeverity }})
                    -- this piece of shit is waiting until the end of the function before execution for some reason
                    vim.api.nvim_win_set_cursor(0, {{ d.lnum + 1, d.col }})
                    if d.lnum ~= line then
                        nextOnAnotherLine = true
                        break
                    end
                    if #diagnostics == 1 then
                        return
                    end
                end
                -- if not, nvim_win_set_cursor will execute after it.
                vim.defer_fn(function() vim.diagnostic.open_float(floatOpts) end, 1)
                return
            end
        end)
        "#,
        request_severity, direction, direction
    );

    let _: () = api::call_function("luaeval", (lua_code,)).unwrap_or(());
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
