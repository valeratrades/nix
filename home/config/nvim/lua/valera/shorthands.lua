G = vim.api.nvim_set_var

-- dict of default vim keymaps. HACK: incomplete by nature
-- Compiled from :help index and vim.rtorr.com
local VIM_DEFAULTS = {
	n = {
		-- Movement
		"h", "j", "k", "l", "gj", "gk", "H", "M", "L", "w", "W", "e", "E", "b", "B", "ge", "gE",
		"%", "0", "^", "$", "g_", "gg", "G", "gd", "gD", "f", "F", "t", "T", ";", ",", "}", "{",
		"(", ")", "[", "]", "zz", "zt", "zb",
		"<C-e>", "<C-y>", "<C-b>", "<C-f>", "<C-d>", "<C-u>",
		-- Editing
		"r", "R", "J", "gJ", "g~", "gu", "gU", "s", "S", "u", "U", "<C-r>", ".",
		-- Marks/Jumps
		"m", "`", "'", "<C-i>", "<C-o>", "<C-]>", "g,", "g;",
		-- Yank/Delete/Paste operators
		"y", "d", "c", "p", "P", "gp", "gP", "x", "X", "Y", "D", "C",
		-- Indent
		">", "<", "=",
		-- Search
		"/", "?", "n", "N", "#", "*", "g*", "g#",
		-- Tabs/Windows
		"gt", "gT", "<C-w>",
		-- Text entry
		"a", "i", "o", "O", "I", "A",
		-- Visual
		"v", "V", "<C-v>",
		-- Folds
		"za", "zo", "zc", "zr", "zm", "zi", "zf", "zd",
		-- Other
		"K", "q", "@", "~", "!", ":", "<tab>", "<CR>", "gf", "gF", "<C-a>", "<C-x>", "ga", "gv", "gw",
	},
	v = {
		-- Movements (most normal mode movements work)
		"h", "j", "k", "l", "w", "W", "e", "E", "b", "B", "0", "^", "$",
		"gg", "G", "f", "F", "t", "T", ";", ",", "}", "{", "(", ")",
		"<C-d>", "<C-u>", "<C-f>", "<C-b>",
		-- Visual mode control
		"v", "V", "<C-v>", "o", "O",
		-- Text objects
		"aw", "ab", "aB", "at", "ib", "iB", "it", "a", "i",
		-- Operations
		">", "<", "y", "d", "c", "~", "u", "U", "r", "s", "x", "J", "gJ",
		"p", "P", ":", "n", "N", "*", "#",
	},
	s = {
		-- Select mode (similar to visual but more limited)
		"<C-g>", "c", "C", "d", "D", "y", "Y", "x", "X",
	},
	o = {
		-- Operator-pending mode (after d, c, y, etc.)
		"h", "j", "k", "l", "w", "W", "e", "E", "b", "B",
		"f", "F", "t", "T", ";", ",", "0", "^", "$",
		"gg", "G", "}", "{", "(", ")", "[", "]",
		"a", "i",        -- text objects
		"v", "V", "<C-v>", -- force motion type
	},
	i = {
		-- Insert mode
		"<C-h>", "<C-w>", "<C-j>", "<C-t>", "<C-d>", "<C-n>", "<C-p>",
		"<C-r>", "<C-o>", "<C-a>", "<C-x>", "<C-e>", "<C-y>",
		"<Esc>", "<C-c>", "<C-[>",
	},
}

function K(mode, lhs, rhs, opts)
	opts = opts or {}
	if opts.noremap == nil then
		opts.noremap = true
	end

	-- Expand "" mode to the modes it actually applies to
	local modes = type(mode) == "table" and mode or { mode }
	local expanded_modes = {}
	for _, m in ipairs(modes) do
		if m == "" then
			-- "" applies to normal, visual, select, and operator-pending
			vim.list_extend(expanded_modes, { "n", "v", "s", "o" })
		else
			table.insert(expanded_modes, m)
		end
	end

	-- Check if mapping already exists (user-defined or vim default)
	local found_existing = false
	for _, m in ipairs(expanded_modes) do
		-- Check user-defined mappings
		local existing = vim.fn.maparg(lhs, m, false, true)
		local is_user_mapped = existing and existing.lhs == lhs

		-- Check vim defaults
		local defaults_for_mode = VIM_DEFAULTS[m] or {}
		local is_vim_default = vim.tbl_contains(defaults_for_mode, lhs)

		if is_user_mapped or is_vim_default then
			found_existing = true
			if not opts.overwrite then
				-- Get caller info
				local info = debug.getinfo(2, "Sl")
				local file = info.source:gsub("^@", ""):gsub(".*/", "")
				local source = is_user_mapped and "user mapping" or "vim default"
				vim.notify(
					string.format("[%s:%d] Keymap conflict: '%s' (mode '%s') overwrites %s", file, info.currentline, lhs, m, source),
					vim.log.levels.WARN
				)
			end
		end
	end

	-- If overwrite was specified but nothing was actually overwritten, warn
	if opts.overwrite and not found_existing then
		local info = debug.getinfo(2, "Sl")
		local file = info.source:gsub("^@", ""):gsub(".*/", "")
		local mode_str = type(mode) == "table" and table.concat(mode, ",") or mode
		vim.notify(
			string.format("[%s:%d] Unnecessary overwrite=true: '%s' (mode '%s') has no existing mapping", file,
				info.currentline, lhs, mode_str),
			vim.log.levels.WARN
		)
	end

	-- Remove overwrite from opts before passing to vim.keymap.set
	local final_opts = vim.tbl_extend("force", opts, {})
	final_opts.overwrite = nil
	vim.keymap.set(mode, lhs, rhs, final_opts)
end

function F(s, mode)
	mode = mode or "n"
	vim.api.nvim_feedkeys(s, mode, false)
end

function Ft(s, mode)
	F(vim.api.nvim_replace_termcodes(s, true, true, true), mode)
end

function Cs()
	if vim.fn.expand("%:e") == "lean" then
		return "--"
	end
	if vim.fn.expand("%:e") == "html" then
		return "//" --don't care for actual html comments there
	end

	local initial = vim.bo.commentstring
	if initial == nil then
		return "//"
	end
	local without_percent_s = string.sub(initial, 1, -3)
	local stripped = string.gsub(without_percent_s, "%s+", "")
	return stripped
end

-- Note that this takes over 1ms defer
function PersistCursor(fn, ...)
	local args = ...
	local cursor_position = vim.api.nvim_win_get_cursor(0)
	local result = fn(args)
	vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, cursor_position) end, 1)
	return result
end

function Echo(text, type)
	type = type or "Comment"
	type = (type:gsub("^%l", string.upper)) -- in case I forget they start from capital letter
	vim.api.nvim_echo({ { text, type } }, false, {})
end

-- -- popups
function GetPopups()
	return vim.fn.filter(vim.api.nvim_tabpage_list_wins(0),
		function(_, e) return vim.api.nvim_win_get_config(e).zindex end)
end

function KillPopups()
	vim.fn.map(GetPopups(), function(_, e)
		vim.api.nvim_win_close(e, false)
	end)
end

function BoolPopupOpen()
	return #GetPopups() > 0
end

--

function PrintQuickfixList()
	local qf_list = vim.fn.getqflist()
	for i, item in ipairs(qf_list) do
		print(string.format("%d: %s", i, vim.inspect(item)))
	end
end

function PNew(lines)
	vim.cmd('new')
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end
