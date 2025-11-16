use nvim_oxi::{api, Array, Dictionary, Function, Object};

/// Helper to defer a Rust callback using vim.defer_fn
pub fn defer_fn<F>(delay_ms: i64, callback: F)
where
    F: Fn() + Send + 'static,
{
    let func = Function::from_fn(move |()| {
        callback();
    });
    let _ = api::call_function::<_, ()>("defer_fn", (Object::from(func), delay_ms));
}

/// Makes a popup with the given text. Sets the filetype to `markdown` to allow for syntax highlighting.
pub fn show_markdown_popup(text: String) {
    // Create buffer via call_function
    let buf: i64 = match api::call_function("nvim_create_buf", (false, true)) {
        Ok(b) => b,
        Err(e) => {
            let _ = api::err_writeln(&format!("Failed to create buffer: {}", e));
            return;
        }
    };

    // Split text into lines
    let lines: Vec<String> = text.lines().map(|s| s.to_string()).collect();
    let lines_array = Array::from_iter(lines.iter().map(|s| Object::from(s.as_str())));

    // Set buffer lines
    if let Err(e) = api::call_function::<_, ()>("nvim_buf_set_lines", (buf, 0, -1, false, lines_array)) {
        let _ = api::err_writeln(&format!("Failed to set buffer lines: {}", e));
        return;
    }

    // Calculate width (max line length)
    let mut width = lines.iter().map(|line| line.len()).max().unwrap_or(0) as i64;
    width = width.max(30 - 4) + 4; // Add padding and ensure minimum width

    // Calculate height
    let height = lines.len() as i64 + 2; // Add padding to height

    // Get editor dimensions
    let editor_lines: i64 = match api::call_function("nvim_get_option", ("lines",)) {
        Ok(l) => l,
        Err(_) => 24,
    };
    let editor_columns: i64 = match api::call_function("nvim_get_option", ("columns",)) {
        Ok(c) => c,
        Err(_) => 80,
    };

    // Calculate centered position
    let row = (editor_lines - height) / 2;
    let col = (editor_columns - width) / 2;

    // Create window options
    let opts = Dictionary::from_iter([
        ("style", Object::from("minimal")),
        ("relative", Object::from("editor")),
        ("width", Object::from(width)),
        ("height", Object::from(height)),
        ("row", Object::from(row)),
        ("col", Object::from(col)),
        ("border", Object::from("rounded")),
        ("title", Object::from(" Popup ")),
        ("title_pos", Object::from("center")),
        ("zindex", Object::from(50_i64)),
    ]);

    // Open the window
    let win: i64 = match api::call_function("nvim_open_win", (buf, true, opts)) {
        Ok(w) => w,
        Err(e) => {
            let _ = api::err_writeln(&format!("Failed to open window: {}", e));
            return;
        }
    };

    // Set keymap to close with 'q'
    let keymap_opts = Dictionary::from_iter([
        ("nowait", Object::from(true)),
        ("noremap", Object::from(true)),
        ("silent", Object::from(true)),
    ]);
    let _ = api::call_function::<_, ()>("nvim_buf_set_keymap", (buf, "n", "q", ":close<CR>", keymap_opts));

    // Enable cursorline for the window
    let _ = api::call_function::<_, ()>("nvim_win_set_option", (win, "cursorline", true));

    // Set filetype to markdown for syntax highlighting
    let _ = api::call_function::<_, ()>("nvim_buf_set_option", (buf, "filetype", "markdown"));
}
