K = vim.keymap.set
G = vim.api.nvim_set_var

function F(s, mode)
	mode = mode or "n"
	vim.api.nvim_feedkeys(s, mode, false)
end

function Ft(s, mode)
	F(vim.api.nvim_replace_termcodes(s, true, true, true), mode)
end

function Cs()
	local initial = vim.bo.commentstring
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
