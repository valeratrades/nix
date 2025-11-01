G = vim.api.nvim_set_var

-- Common vim default keys that are often remapped
local VIM_DEFAULTS = {
	n = { "h", "j", "k", "l", "s", "S", "r", "R", "n", "N", "t", "T", "c", "C", "d", "D", "y", "Y", "x", "X", "H", "M", "L", "J", "gf", "gF", "U", "<tab>", ";", ":", "<C-d>", "<C-u>", "<C-o>", "<C-i>", "<C-r>", "<C-a>", "<C-x>" },
	v = { "h", "j", "k", "l", "s", "S", "r", "R", "n", "N", "t", "T", "c", "C", "d", "D", "y", "Y", "x", "X", ";", ":", "<C-d>", "<C-u>", "<C-o>", "<C-i>", "<C-r>", "<C-a>", "<C-x>" },
	s = { "h", "j", "k", "l", "c", "C", "d", "D", "y", "Y", "x", "X" },
	o = { "h", "j", "k", "l", "t", "T" },
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
			string.format("[%s:%d] Unnecessary overwrite=true: '%s' (mode '%s') has no existing mapping", file, info.currentline, lhs, mode_str),
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
