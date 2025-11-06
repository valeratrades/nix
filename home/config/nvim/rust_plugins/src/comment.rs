use nvim_oxi::api;
use nvim_oxi::String as NvimString;
use crate::shorthands::{infer_comment_string, f};

/// Add foldmarker comment block around selection
pub fn foldmarker_comment_block(nesting_level: i64) {
    let cs_str = infer_comment_string();

    // Disable copilot
    let _ = api::set_var("b:copilot_enabled", false);

    // Move to end of selection and add closing marker
    let _ = api::feedkeys(&NvimString::from(format!("o{},}}}}}}}}{}", cs_str, nesting_level)), &NvimString::from("n"), false);

    // Move to start of selection
    let _ = api::feedkeys(&NvimString::from("`<"), &NvimString::from("n"), false);

    // Add opening marker
    let _ = api::feedkeys(&NvimString::from(format!("O{}  {{{{{{{{{}", cs_str, nesting_level)), &NvimString::from("n"), false);

    // Position cursor
    let _ = api::feedkeys(&NvimString::from("hhhhi"), &NvimString::from("n"), false);
}

/// Draw a big beautiful line with the given symbol
pub fn draw_a_big_beautiful_line(symbol: char) {
    let cs_str = infer_comment_string();
    let prefix = if cs_str.len() == 1 {
        format!("{}{}", cs_str, symbol)
    } else {
        cs_str.clone()
    };

    let line: String = std::iter::repeat(symbol).take(77).collect();
    let full_line = format!("{}{}", prefix, line);

    let _ = api::feedkeys(&NvimString::from(full_line), &NvimString::from("n"), false);
    let _ = api::feedkeys(&NvimString::from("0"), &NvimString::from("t"), false);
}

/// Remove end-of-line comment
pub fn remove_end_of_line_comment() {
    // Save cursor position
    let save_cursor = api::get_current_win()
        .get_cursor()
        .unwrap_or((1, 0));

    let cs_str = infer_comment_string();

    // Search backwards for " {comment_string}"
    let search_pattern = format!("$ {} ", cs_str);
    let _ = api::feedkeys(&NvimString::from(format!("?{}", search_pattern)), &NvimString::from("t"), false);
    let _ = api::feedkeys(&NvimString::from("cr"), &NvimString::from("t"), false);

    // Delete from cursor to end of line (excluding trailing whitespace)
    let _ = api::feedkeys(&NvimString::from("vg_d"), &NvimString::from("t"), false);

    // Remove trailing whitespace
    api::command("s/\\s\\+$//e").ok();

    // Restore cursor position
    let mut win = api::get_current_win();
    let _ = win.set_cursor(save_cursor.0, save_cursor.1);

    // Clear search highlight
    let _ = api::command("noh");
}

/// Add or remove debug comments
pub fn debug_comment(action: &str) {
    let cs_str = infer_comment_string();

    match action {
        "add" => {
            let dbg_comment = format!(" {}dbg", cs_str);
            let _ = api::feedkeys(&NvimString::from(":"), &NvimString::from("n"), false);
            let _ = api::feedkeys(&NvimString::from(format!("s/$/{}/g", dbg_comment)), &NvimString::from("n"), false);
            let _ = api::feedkeys(&NvimString::from("cr"), &NvimString::from("t"), false);

            // Clear highlight and message
            std::thread::sleep(std::time::Duration::from_millis(3));
            let _ = api::command("noh");
        }
        "remove" => {
            let _ = api::command(&format!("g/ {}dbg$/d", cs_str));
            let _ = api::command("g/\\sdbg!(/d");
            let _ = api::command("noh");
        }
        _ => {}
    }
}

/// Add TODO comment with given number of exclamation marks
pub fn add_todo_comment(n: i64) {
    // Disable copilot
    let _ = api::set_var("b:copilot_enabled", false);

    let cs_str = infer_comment_string();
    let exclamations: String = std::iter::repeat('!').take(n as usize).collect();
    let todo_line = format!("O{}TODO{}: ", cs_str, exclamations);

    let _ = api::feedkeys(&NvimString::from(todo_line), &NvimString::from("n"), false);
}

// Global state for toggle comments visibility
static mut COMMENTS_ON: bool = true;

/// Toggle comments visibility
pub fn toggle_comments_visibility() {
    unsafe {
        COMMENTS_ON = !COMMENTS_ON;

        if !COMMENTS_ON {
            // Hide comments by setting fg to background color
            let _ = api::exec2(
                r#"
                let s:original_hl = nvim_get_hl(0, {'name': 'Comment'})
                let l:custom = nvim_get_hl(0, {'name': 'CustomGroup'})
                if has_key(l:custom, 'bg')
                    call nvim_set_hl(0, 'Comment', {'fg': l:custom.bg})
                endif
                "#,
                &Default::default(),
            );
        } else {
            // Restore original highlight
            let _ = api::exec2(
                r#"
                if exists('s:original_hl')
                    call nvim_set_hl(0, 'Comment', s:original_hl)
                endif
                "#,
                &Default::default(),
            );
        }
    }
}

/// Comment extra reimplementation
/// Disables copilot and inserts the given leader followed by comment string
pub fn comment_extra_reimplementation(insert_leader: String) {
    // Disable copilot
    let _ = api::set_var("b:copilot_enabled", false);

    // Feed the insert leader
    f(insert_leader, None);

    // Feed the comment string with a space
    let cs = infer_comment_string();
    f(format!("{} ", cs), None);
}
