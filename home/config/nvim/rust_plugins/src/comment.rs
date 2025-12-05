use nvim_oxi::api;
use nvim_oxi::String as NvimString;
use crate::shorthands::{infer_comment_string, f, ft};
use crate::utils::defer_fn;

/// Temporarily disable copilot and set up an autocmd to re-enable it on InsertLeave
fn disable_copilot_temporarily() {
    let _ = api::set_var("b:copilot_enabled", false);

    // Create a one-shot autocmd to re-enable copilot when leaving insert mode
    let lua_code = r#"
        vim.api.nvim_create_autocmd('InsertLeave', {
            once = true,
            callback = function()
                vim.b.copilot_enabled = true
            end,
        })
    "#;
    let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
}

/// Add foldmarker comment block around selection
pub fn foldmarker_comment_block(nesting_level: i64) {
    let cs_str = infer_comment_string();

    disable_copilot_temporarily();

    // Original Lua: F('o' .. cs .. ',}}}' .. nesting_level)
    f(format!("o{},}}}}}}{}", cs_str, nesting_level), None);

    // Original Lua: Ft('<Esc>`<')
    ft(format!("<Esc>`<"), None);

    // Original Lua: F('O' .. cs .. '  ' .. '{{{' .. nesting_level)
    f(String::from("O") + &cs_str + "  {{{" + &nesting_level.to_string(), None);

    // Original Lua: Ft('<Esc>hhhhi')
    ft(format!("<Esc>hhhhi"), None);
}

/// Remove end-of-line comment
pub fn remove_end_of_line_comment() {
    // Save cursor position
    let save_cursor = api::get_current_win()
        .get_cursor()
        .unwrap_or((1, 0));

    let cs_str = infer_comment_string();

    // Search backwards for " {comment_string}" from end of line
    // Original Lua: Ft("$?" .. " " .. Cs() .. "<cr>")
    ft(format!("$? {}<cr>", cs_str), None);

    // Delete from cursor to end of line (excluding trailing whitespace)
    // Original Lua: Ft("vg_d")
    ft("vg_d".to_string(), None);

    // Remove trailing whitespace (with defer)
    // Original Lua: vim.defer_fn(function() vim.cmd([[s/\s\+$//e]]) end, 1)
    defer_fn(1, || {
        let _ = api::command("s/\\s\\+$//e");
    });

    // Restore cursor position (with defer)
    // Original Lua: vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, save_cursor) end, 2)
    defer_fn(2, move || {
        let _ = api::get_current_win().set_cursor(save_cursor.0, save_cursor.1);
    });

    // Clear search highlight (with defer)
    // Original Lua: vim.defer_fn(function() vim.cmd.noh() end, 3)
    defer_fn(3, || {
        let _ = api::command("noh");
    });
}

/// Add or remove debug comments
pub fn debug_comment(action: &str) {
    let cs_str = infer_comment_string();

    match action {
        "add" => {
            // Original Lua: local dbg_comment = " " .. Cs() .. "dbg"
            let dbg_comment = format!(" {}dbg", cs_str);

            // Original Lua: F(':')
            f(":".to_string(), None);

            // Original Lua: F("s/$/" .. dbg_comment .. "/g")
            f(format!("s/$/{}/g", dbg_comment), None);

            // Original Lua: PersistCursor(Ft, "<cr>")
            // PersistCursor saves cursor, calls function, then restores cursor with defer_fn
            let cursor_position = api::get_current_win()
                .get_cursor()
                .unwrap_or((1, 0));
            ft("<cr>".to_string(), None);

            // Restore cursor (with defer_fn timing of 1ms like PersistCursor)
            defer_fn(1, move || {
                let _ = api::get_current_win().set_cursor(cursor_position.0, cursor_position.1);
            });

            // Original Lua: vim.defer_fn(function() vim.cmd.noh() end, 3)
            defer_fn(3, || {
                let _ = api::command("noh");
            });

            // Original Lua: vim.defer_fn(function() Echo("") end, 4)
            defer_fn(4, || {
                crate::lsp::echo("".to_string(), None);
            });
        }
        "remove" => {
            // Original Lua: vim.cmd("g/" .. " " .. cs .. "dbg$/d")
            let _ = api::command(&format!("g/ {}dbg$/d", cs_str));

            // Original Lua: vim.cmd([[g/\sdbg!(/d]])
            let _ = api::command("g/\\sdbg!(/d");

            // Original Lua: vim.cmd.noh()
            let _ = api::command("noh");
        }
        _ => {}
    }
}

/// Add TODO comment with given number of exclamation marks
pub fn add_todo_comment(n: i64) {
    disable_copilot_temporarily();

    let cs_str = infer_comment_string();
    let exclamations: String = std::iter::repeat('!').take(n as usize).collect();
    let todo_line = format!("O{}TODO{}: ", cs_str, exclamations);

    let _ = api::feedkeys(&NvimString::from(todo_line), &NvimString::from("n"), false);
}

/// Toggle comments visibility
pub fn toggle_comments_visibility() {
    // Get current state from Lua global variables
    // Original Lua uses: local on = 1, local original
    let on: i64 = api::get_var("_rust_toggle_comments_on")
        .unwrap_or(1);

    // Toggle: on = 1 - on
    let new_on = 1 - on;
    let _ = api::set_var("_rust_toggle_comments_on", new_on);

    if new_on == 0 {
        // Hide comments by setting fg to background color
        // Original Lua: original = vim.api.nvim_get_hl(0, { name = "Comment" })
        let lua_code = r#"
            local original = vim.api.nvim_get_hl(0, { name = "Comment" })
            vim.g._rust_toggle_comments_original = original
            local custom_group = vim.api.nvim_get_hl(0, { name = "CustomGroup" })
            vim.api.nvim_set_hl(0, "Comment", { fg = custom_group.bg })
        "#;
        let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
    } else {
        // Restore original highlight
        // Original Lua: vim.api.nvim_set_hl(0, "Comment", original)
        let lua_code = r#"
            local original = vim.g._rust_toggle_comments_original
            if original then
                vim.api.nvim_set_hl(0, "Comment", original)
            end
        "#;
        let _ = api::call_function::<_, ()>("luaeval", (lua_code,));
    }
}

/// Comment extra reimplementation
/// Disables copilot temporarily and inserts the given leader followed by comment string
pub fn comment_extra_reimplementation(insert_leader: String) {
    disable_copilot_temporarily();

    // Feed the insert leader
    f(insert_leader, None);

    // Feed the comment string with a space
    let cs = infer_comment_string();
    f(format!("{} ", cs), None);
}
