--[[
file for temporary functions.

# Usage
`:source ~/.config/nvim/lua/valera/tmp.lua` directly
and then just use the commands normally

# NB
any and all functions in this file should be deletable at any time. Nothing important ever goes here.
]]

vim.api.nvim_create_user_command("Dbg", function()
	local lines = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.zindex then
			table.insert(lines, "win: " .. win)
			for k, v in pairs(cfg) do
				table.insert(lines, "  " .. k .. ": " .. tostring(v))
			end
			local buf = vim.api.nvim_win_get_buf(win)
			table.insert(lines, "  buf: " .. buf)
			table.insert(lines, "  bufname: " .. vim.api.nvim_buf_get_name(buf))
			table.insert(lines, "  ft: " .. vim.bo[buf].filetype)
			table.insert(lines, "  win vars:")
			for k, v in pairs(vim.w[win]) do
				table.insert(lines, "    " .. k .. ": " .. tostring(v))
			end
			local ok1, v1 = pcall(vim.api.nvim_win_get_var, win, "treesitter_context")
			table.insert(lines, "  treesitter_context: " .. tostring(ok1) .. " " .. tostring(v1))
			local ok2, v2 = pcall(vim.api.nvim_win_get_var, win, "treesitter_context_line_number")
			table.insert(lines, "  treesitter_context_line_number: " .. tostring(ok2) .. " " .. tostring(v2))
		end
	end
	local f = io.open("/tmp/nvim_dbg_out.txt", "w")
	if f then
		f:write(table.concat(lines, "\n"))
		f:close()
		print("Wrote to /tmp/nvim_dbg_out.txt")
	end
end, {})
