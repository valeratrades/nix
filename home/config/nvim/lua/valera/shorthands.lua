G = vim.api.nvim_set_var

function K(mode, lhs, rhs, opts)
	opts = opts or {}
	-- Get caller info before calling into Rust
	local info = debug.getinfo(2, "Sl")
	local caller = string.format("%s:%d", info.source:gsub("^@", ""):gsub(".*/", ""), info.currentline)
	opts._caller = caller
	require('rust_plugins').smart_keymap(mode, lhs, rhs, opts)
end

function Cs()
	return require('rust_plugins').infer_comment_string()
end

-- Note that this takes over 1ms defer
function PersistCursor(fn, ...)
	local args = ...
	local cursor_position = vim.api.nvim_win_get_cursor(0)
	local result = fn(args)
	vim.defer_fn(function() vim.api.nvim_win_set_cursor(0, cursor_position) end, 1)
	return result
end

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
