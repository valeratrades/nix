use nvim_oxi::{
	api::{
		self,
		types::{WindowAnchor, WindowBorder, WindowConfig, WindowRelativeTo, WindowStyle},
	},
	Dictionary, Function, Object,
};

/// Helper to defer a Rust callback using vim.defer_fn
pub fn defer_fn<F>(delay_ms: i64, callback: F)
where
	F: Fn() + Send + 'static, {
	let func = Function::from_fn(move |()| {
		callback();
	});
	let _ = api::call_function::<_, ()>("defer_fn", (Object::from(func), delay_ms));
}

/// A highlight to apply to a line in the popup
pub struct LineHighlight {
	pub line: usize,      // 0-indexed line number
	pub col_start: usize, // byte offset start
	pub col_end: usize,   // byte offset end
	pub hl_group: String, // highlight group name
}

/// Options for showing a popup
#[derive(Default)]
pub struct PopupOptions {
	/// If true, position relative to cursor; if false, center in editor
	pub sticky: bool,
	/// Highlights to apply to specific ranges
	pub highlights: Vec<LineHighlight>,
}

/// Makes a popup with the given text. Sets the filetype to `markdown` to allow for syntax highlighting.
pub fn show_markdown_popup(text: String) {
	show_popup_with_options(text, PopupOptions::default());
}

/// Makes a popup with the given text and options.
pub fn show_popup_with_options(text: String, options: PopupOptions) {
	// Create scratch buffer
	let mut buf = match api::create_buf(false, true) {
		Ok(b) => b,
		Err(e) => {
			api::err_writeln(&format!("Failed to create buffer: {e}"));
			return;
		}
	};

	// Split text into lines
	let lines: Vec<&str> = text.lines().collect();

	// Set buffer lines
	if let Err(e) = buf.set_lines(0.., true, lines.clone()) {
		api::err_writeln(&format!("Failed to set buffer lines: {e}"));
		return;
	}

	// Calculate width (max line length, minimum 10)
	let width = lines.iter().map(|line| line.chars().count()).max().unwrap_or(10).max(10) as u32;

	// Calculate height
	let height = lines.len() as u32;

	// Build window config based on sticky option
	let config = if options.sticky {
		// Position relative to cursor
		// Check if there's enough space above cursor, otherwise go below
		let cursor_row: i64 = api::call_function("line", (".".to_string(),)).unwrap_or(1);
		let win_height: i64 = api::call_function("winheight", (0,)).unwrap_or(24);

		// If cursor is in the top half, show below; otherwise show above
		let (row_offset, anchor) = if cursor_row < win_height / 2 {
			// Show below cursor (NW anchor = top-left at position)
			(1.0, WindowAnchor::NorthWest)
		} else {
			// Show above cursor (SW anchor = bottom-left at position)
			(0.0, WindowAnchor::SouthWest)
		};

		WindowConfig::builder()
			.relative(WindowRelativeTo::Cursor)
			.anchor(anchor)
			.row(row_offset)
			.col(0)
			.width(width)
			.height(height)
			.style(WindowStyle::Minimal)
			.border(WindowBorder::Rounded)
			.focusable(true)
			.build()
	} else {
		// Center in editor
		let editor_lines: i64 = api::call_function("nvim_get_option", ("lines",)).unwrap_or(24);
		let editor_columns: i64 = api::call_function("nvim_get_option", ("columns",)).unwrap_or(80);

		let row = ((editor_lines - height as i64) / 2).max(0);
		let col = ((editor_columns - width as i64) / 2).max(0);

		WindowConfig::builder()
			.relative(WindowRelativeTo::Editor)
			.row(row as f64)
			.col(col as f64)
			.width(width)
			.height(height)
			.style(WindowStyle::Minimal)
			.border(WindowBorder::Rounded)
			.focusable(true)
			.build()
	};

	// Open the window (don't enter it if sticky)
	let win = match api::open_win(&buf, !options.sticky, &config) {
		Ok(w) => w,
		Err(e) => {
			api::err_writeln(&format!("Failed to open window: {e}"));
			return;
		}
	};

	// Apply highlights
	for hl in &options.highlights {
		let _ = api::call_function::<_, ()>(
			"nvim_buf_add_highlight",
			(buf.handle(), -1i64, hl.hl_group.as_str(), hl.line as i64, hl.col_start as i64, hl.col_end as i64),
		);
	}

	// Set keymap to close with 'q'
	let keymap_opts = Dictionary::from_iter([("nowait", Object::from(true)), ("noremap", Object::from(true)), ("silent", Object::from(true))]);
	let _ = api::call_function::<_, ()>("nvim_buf_set_keymap", (buf.handle(), "n", "q", ":close<CR>", keymap_opts));

	// Set buffer options
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("modifiable", false, Dictionary::from_iter([("buf", Object::from(buf.handle()))])));
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("bufhidden", "wipe", Dictionary::from_iter([("buf", Object::from(buf.handle()))])));

	if !options.sticky {
		// Enable cursorline for centered popups
		let _ = api::call_function::<_, ()>("nvim_set_option_value", ("cursorline", true, Dictionary::from_iter([("win", Object::from(win.handle()))])));
	}

	// Set filetype to markdown for syntax highlighting
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("filetype", "markdown", Dictionary::from_iter([("buf", Object::from(buf.handle()))])));

	// For sticky popups, close on cursor move
	if options.sticky {
		let win_handle = win.handle();
		let lua_code = format!(
			r#"
            vim.api.nvim_create_autocmd({{"CursorMoved", "CursorMovedI", "BufLeave"}}, {{
                buffer = vim.api.nvim_get_current_buf(),
                once = true,
                callback = function()
                    if vim.api.nvim_win_is_valid({win_handle}) then
                        vim.api.nvim_win_close({win_handle}, true)
                    end
                end,
            }})
            "#
		);
		let _ = api::call_function::<_, ()>("nvim_exec2", (lua_code, Dictionary::new()));
	}
}
