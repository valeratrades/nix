G = vim.api.nvim_set_var

function K(mode, lhs, rhs, opts)
	opts = opts or {}
	if opts.noremap == nil then
		opts.noremap = true
	end

	-- Check if mapping already exists
	local modes = type(mode) == "table" and mode or { mode }
	local found_existing = false
	for _, m in ipairs(modes) do
		local existing = vim.fn.maparg(lhs, m, false, true)
		if existing and existing.lhs == lhs then
			found_existing = true
			if not opts.overwrite then
				-- Get caller info
				local info = debug.getinfo(2, "Sl")
				local file = info.source:gsub("^@", ""):gsub(".*/", "")
				vim.notify(
					string.format("[%s:%d] Keymap conflict: '%s' (mode '%s') already mapped", file, info.currentline, lhs, m),
					vim.log.levels.WARN
				)
			end
		end
	end

	-- If overwrite was specified but nothing was actually overwritten, warn
	if opts.overwrite and not found_existing then
		local info = debug.getinfo(2, "Sl")
		local file = info.source:gsub("^@", ""):gsub(".*/", "")
		vim.notify(
			string.format("[%s:%d] Unnecessary overwrite=true: '%s' (mode '%s') has no existing mapping", file,
				info.currentline, lhs, table.concat(modes, ",")),
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
