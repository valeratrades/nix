-- Track closed tabs for reopen with Ctrl+Shift+T
do
	local tab_buffers = {}    -- tabnr -> list of file paths (snapshot before leave)
	local closed_tabs = {}    -- stack of {files, cwd}

	vim.api.nvim_create_autocmd("TabLeave", {
		callback = function()
			local tabnr = vim.api.nvim_get_current_tabpage()
			local wins = vim.api.nvim_tabpage_list_wins(tabnr)
			local files = {}
			for _, win in ipairs(wins) do
				local buf = vim.api.nvim_win_get_buf(win)
				local name = vim.api.nvim_buf_get_name(buf)
				if name ~= "" and vim.bo[buf].buftype == "" then
					files[#files + 1] = name
				end
			end
			tab_buffers[tabnr] = { files = files, cwd = vim.fn.getcwd(-1, vim.fn.tabpagenr()) }
		end,
		desc = "Snapshot tab buffers before leaving",
	})

	vim.api.nvim_create_autocmd("TabClosed", {
		callback = function(args)
			local tabnr = tonumber(args.file)
			local saved = tab_buffers[tabnr]
			if saved and #saved.files > 0 then
				closed_tabs[#closed_tabs + 1] = saved
			end
			tab_buffers[tabnr] = nil
		end,
		desc = "Push closed tab buffers to reopen stack",
	})

	function ReopenLastClosedTab()
		if #closed_tabs == 0 then
			vim.notify("No closed tabs to reopen", vim.log.levels.INFO)
			return
		end
		local entry = table.remove(closed_tabs)
		vim.cmd("tabnew")
		if entry.cwd then
			vim.cmd("tcd " .. vim.fn.fnameescape(entry.cwd))
		end
		local first = true
		for _, path in ipairs(entry.files) do
			if first then
				vim.cmd("edit " .. vim.fn.fnameescape(path))
				first = false
			else
				vim.cmd("vsplit " .. vim.fn.fnameescape(path))
			end
		end
	end
end

-- Save/restore views (folds, cursor) - skip special buffers like oil
vim.api.nvim_create_autocmd("BufWinLeave", {
	callback = function()
		if vim.bo.buftype == "" and vim.bo.filetype ~= "oil" then
			vim.cmd("silent! mkview")
		end
	end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
	callback = function()
		if vim.bo.buftype == "" and vim.bo.filetype ~= "oil" then
			vim.cmd("silent! loadview")
		end
	end,
})

vim.cmd [[
  autocmd FileType * :set formatoptions-=ro
	autocmd VimEnter,WinNew,BufWinEnter * lua vim.fn.chdir(vim.env.PWD)
]]

--TODO!!!: make it work when opening a new editor instance on a file
--vim.api.nvim_create_autocmd({ "FileType" }, {
--	pattern = { "lean", "yaml", "yml", "py", "mojo" }, -- for rust I think it's not worth it, as I'd pay with time for like 0.05% of times that I actuall yneed this in it
--	callback = function()
--		vim.cmd("GuessIndent")
--	end,
--})

vim.api.nvim_create_autocmd({ "FileType" }, {
	pattern = { "lean", "yaml", "yml" },
	callback = function()
		vim.opt_local.expandtab = true
	end,
})



--TEST: if all good, try expanding to other languages. Auto-importing for rust could be great
vim.api.nvim_create_autocmd({ "BufWritePost" }, {
	pattern = { "*.py" },
	callback = function(args)
		local bufnr = args.buf
		local clients = vim.lsp.get_clients({ bufnr = bufnr })
		for _, client in ipairs(clients) do
			if client:supports_method("textDocument/codeAction") then
				vim.lsp.buf.code_action({
					apply = true,
					context = { only = { "source.fixAll" }, diagnostics = {} },
				})
				break
			end
		end
	end,
	desc = "LSP: Fix all auto-fixable issues on save (source.fixAll)",
})


--vim.cmd([[ autocmd BufWritePost *.sh silent !chmod +x <afile> ]])
vim.api.nvim_create_autocmd({ "BufWritePost" }, {
	pattern = { "*.sh", "*.zsh", "*.bash", "*.fish", "*.xsh", "*script.rs" },
	callback = function()
		os.execute('chmod +x ' .. vim.fn.expand('%:p'))
	end,
})



-- Use 'q' to quit from common plugins
vim.api.nvim_create_autocmd({ "FileType" }, {
	pattern = { "qf", "help", "man", "lspinfo", "spectre_panel", "lir", "peek" },
	callback = function()
		vim.cmd([[
      nnoremap <silent> <buffer> q :close<CR>
      set nobuflisted
    ]])
	end,
})

-- Set wrap and spell in markdown and gitcommit
vim.api.nvim_create_autocmd({ "FileType" }, {
	pattern = { "gitcommit", "markdown", "typst" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- Disable undo file for .env files
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
	pattern = { "*.env" },
	callback = function()
		vim.opt_local.undofile = false
	end,
})

-- 3-way merge on external file change: preserves unsaved buffer edits
-- Snapshots the "base" (last known disk state) on read and write.
-- On FileChangedShell, merges: base × buffer × new_disk via `git merge-file`.
do
	local base_snapshots = {} -- bufnr -> lines (string)

	local function snapshot_base(bufnr)
		local path = vim.api.nvim_buf_get_name(bufnr)
		if path == "" or vim.bo[bufnr].buftype ~= "" then return end
		local f = io.open(path, "r")
		if f then
			base_snapshots[bufnr] = f:read("*a")
			f:close()
		end
	end

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		callback = function(args) snapshot_base(args.buf) end,
		desc = "Snapshot file base for 3-way merge",
	})

	-- Clean up snapshots when buffers are deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args) base_snapshots[args.buf] = nil end,
	})

	vim.api.nvim_create_autocmd("FileChangedShell", {
		callback = function(args)
			local bufnr = args.buf
			local path = vim.api.nvim_buf_get_name(bufnr)

			-- If buffer is not modified, just reload
			if not vim.bo[bufnr].modified then
				vim.v.fcs_choice = "reload"
				-- Update snapshot to new disk state
				vim.schedule(function() snapshot_base(bufnr) end)
				return
			end

			local base = base_snapshots[bufnr]
			if not base then
				-- No base snapshot (shouldn't happen), fall back to plain reload
				vim.v.fcs_choice = "reload"
				vim.schedule(function() snapshot_base(bufnr) end)
				return
			end

			-- Read new disk content
			local f = io.open(path, "r")
			if not f then
				vim.v.fcs_choice = "reload"
				return
			end
			local theirs = f:read("*a")
			f:close()

			-- Get current buffer content
			local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local mine = table.concat(buf_lines, "\n") .. "\n"

			-- Tell nvim we're handling it
			vim.v.fcs_choice = ""

			local rp = require("rust_plugins")
			local merged, had_conflicts = rp.three_way_merge(base, mine, theirs)

			-- Split merged content into lines (drop trailing empty line from final \n)
			local new_lines = vim.split(merged, "\n", { plain = true })
			if new_lines[#new_lines] == "" then
				table.remove(new_lines)
			end

			-- Save cursor position
			local cursor = vim.api.nvim_win_get_cursor(0)

			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

			-- Restore cursor (clamp to new line count)
			local max_line = vim.api.nvim_buf_line_count(bufnr)
			cursor[1] = math.min(cursor[1], max_line)
			vim.api.nvim_win_set_cursor(0, cursor)

			-- Update base snapshot to new disk state
			base_snapshots[bufnr] = theirs

			if had_conflicts then
				vim.notify("Overlapping edits were overwritten by disk version", vim.log.levels.WARN)
			end
		end,
		desc = "3-way merge external changes with unsaved buffer edits",
	})
end
