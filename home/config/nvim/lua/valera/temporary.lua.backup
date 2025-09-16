-- https://github.com/neovim/neovim/issues/30985
for _, method in ipairs({ 'textDocument/diagnostic', 'workspace/diagnostic' }) do
	local default_diagnostic_handler = vim.lsp.handlers[method]
	vim.lsp.handlers[method] = function(err, result, context, config)
		if err ~= nil and err.code == -32802 then
			return
		end
		return default_diagnostic_handler(err, result, context, config)
	end
end

-- prevent warnings and errors from blocking ui
function vim.notify(msg, level, opts)
	if level == vim.log.levels.ERROR then
		print('error:', msg)
	elseif level == vim.log.levels.WARN then
		print('warn:', msg)
	else
		print('info:', msg)
	end
end

-- The following is copied from another guy who (allegedly) was trying to solve the same problem. Haven't checked yet.
--local orig_notify = vim.notify
--local new_notify = require("notify")
--
--local normal_notify = { "nvim-tree.lua" }
--
--vim.notify = function(msg, level, opts)
--    local info = debug.getinfo(2, "S")
--    local source = string.replace(info.source, "@", "")
--    local found = false
--
--    if opts and opts["normal_notify"] ~= nil and opts["normal_notify"] then
--        found = true
--    else
--        for _, item in ipairs(normal_notify) do
--            if string.find(source, item, 1, true) then
--                found = true
--                break
--            end
--        end
--    end
--
--    if found then
--        orig_notify(msg, level, opts)
--    else
--        new_notify(msg, level, opts)
--    end
--end

---- README:
---- , for change
---- . for scrolling to the next
---- ' to prev
--
--
-- local path = os.getenv("HOME") .. "/s/training-data/line_checkpoint.txt"
--
-- function dump_line_number()
--   local line_number = vim.fn.line(".")
--   local file = io.open(path, "w")
--   file:write(tostring(line_number))
--   file:close()
-- end
--
-- function go_to_checkpoint()
--   local file = io.open(path, "r")
--   local line_number = file:read("*l")
--   file:close()
--   vim.api.nvim_command(":" .. line_number)
-- end
--
-- vim.api.nvim_set_keymap('n', "'", 'a<BS>0<Esc>', { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', '.', '/\\"classification\\":\\s\\"\\+<CR>f"A<Esc>hi<cmd>lua dump_line_number()<CR>', { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', ",", 'k?\\"classification\\":\\s\\"\\+<CR>f"Ahi<cmd>lua dump_line_number()<CR>', { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', "p", ':lua go_to_checkpoint()<CR>A<Esc>', { noremap = true, silent = true })
--
--
----TODO: make a keybind to source this file from normal mode, and remove its mention from the local init.lua.
