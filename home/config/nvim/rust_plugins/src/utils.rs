use nvim_oxi::{
	api::{self},
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
/// Uses luaeval to call nvim_open_win, bypassing nvim-oxi's WindowConfig serialization
/// which has broken mask bit ordering on nvim 0.12.
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
	let width = lines.iter().map(|line| line.chars().count()).max().unwrap_or(10).max(10);

	// Calculate height (minimum 1 to avoid Neovim error)
	let height = lines.len().max(1);

	let bufnr = buf.handle();
	let enter = !options.sticky;

	// Build and execute nvim_open_win via Lua to avoid nvim-oxi mask bit mismatch
	let (relative, anchor, row, col) = if options.sticky {
		let cursor_row: i64 = api::call_function("line", (".".to_string(),)).unwrap_or(1);
		let win_height: i64 = api::call_function("winheight", (0,)).unwrap_or(24);
		if cursor_row < win_height / 2 {
			("cursor", "NW", 1i64, 0i64)
		} else {
			("cursor", "SW", 0i64, 0i64)
		}
	} else {
		let editor_lines: i64 = api::call_function("nvim_get_option", ("lines",)).unwrap_or(24);
		let editor_columns: i64 = api::call_function("nvim_get_option", ("columns",)).unwrap_or(80);
		let r = ((editor_lines - height as i64) / 2).max(0);
		let c = ((editor_columns - width as i64) / 2).max(0);
		("editor", "NW", r, c)
	};

	let lua_code = format!(
		r#"return vim.api.nvim_open_win({bufnr}, {enter}, {{
			relative = "{relative}",
			anchor = "{anchor}",
			row = {row},
			col = {col},
			width = {width},
			height = {height},
			style = "minimal",
			border = "rounded",
			focusable = true,
		}})"#
	);

	let win_id: i64 = match api::call_function("luaeval", (lua_code,)) {
		Ok(id) => id,
		Err(e) => {
			api::err_writeln(&format!("Failed to open window: {e}"));
			return;
		}
	};

	// Apply highlights
	for hl in &options.highlights {
		let _ = api::call_function::<_, ()>(
			"nvim_buf_add_highlight",
			(bufnr, -1i64, hl.hl_group.as_str(), hl.line as i64, hl.col_start as i64, hl.col_end as i64),
		);
	}

	// Set keymap to close with 'q'
	let keymap_opts = Dictionary::from_iter([("nowait", Object::from(true)), ("noremap", Object::from(true)), ("silent", Object::from(true))]);
	let _ = api::call_function::<_, ()>("nvim_buf_set_keymap", (bufnr, "n", "q", ":close<CR>", keymap_opts));

	// Set buffer options
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("modifiable", false, Dictionary::from_iter([("buf", Object::from(bufnr))])));
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("bufhidden", "wipe", Dictionary::from_iter([("buf", Object::from(bufnr))])));

	if !options.sticky {
		// Enable cursorline for centered popups
		let _ = api::call_function::<_, ()>("nvim_set_option_value", ("cursorline", true, Dictionary::from_iter([("win", Object::from(win_id))])));
	}

	// Set filetype to markdown for syntax highlighting
	let _ = api::call_function::<_, ()>("nvim_set_option_value", ("filetype", "markdown", Dictionary::from_iter([("buf", Object::from(bufnr))])));

	// For sticky popups, close on cursor move
	if options.sticky {
		let lua_code = format!(
			r#"
            vim.api.nvim_create_autocmd({{"CursorMoved", "CursorMovedI", "BufLeave"}}, {{
                buffer = vim.api.nvim_get_current_buf(),
                once = true,
                callback = function()
                    if vim.api.nvim_win_is_valid({win_id}) then
                        vim.api.nvim_win_close({win_id}, true)
                    end
                end,
            }})
            "#
		);
		let _ = api::call_function::<_, ()>("nvim_exec2", (lua_code, Dictionary::new()));
	}
}
