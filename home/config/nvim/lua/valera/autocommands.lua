-- Ctrl+Shift+T: reopen the last closed window in its old spot, or the whole tab if the tab is what got closed
do
	local closed = {} -- stack of {tab?, wins = old id -> snapshot, layout, sizes, cwd, focus}; no `tab` means a closed tab
	local moved = {} -- old win id -> window reopened in its place, so older snapshots still resolve

	local function live(id, tab)
		while moved[id] do id = moved[id] end
		if vim.api.nvim_win_is_valid(id) and vim.api.nvim_win_get_tabpage(id) == tab then return id end
	end
	local function restorable(s)
		return vim.api.nvim_buf_is_valid(s.buf) or (s.path ~= "" and s.buftype ~= "terminal")
	end
	local reopenable_buftypes = { [""] = true, acwrite = true, help = true, terminal = true } -- the rest are plugin UI

	vim.api.nvim_create_autocmd("WinClosed", {
		callback = function(args)
			local win = tonumber(args.match)
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_win_get_config(win).relative ~= "" or not reopenable_buftypes[vim.bo[buf].buftype] then return end
			local tab = vim.api.nvim_win_get_tabpage(win)
			local tabnr = vim.api.nvim_tabpage_get_number(tab)
			local sizes = {}
			for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				sizes[w] = { vim.api.nvim_win_get_width(w), vim.api.nvim_win_get_height(w) }
			end
			closed[#closed + 1] = {
				tab = tab,
				wins = { [win] = {
					buf = buf,
					path = vim.api.nvim_buf_get_name(buf),
					buftype = vim.bo[buf].buftype,
					listed = vim.bo[buf].buflisted,
					view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
				} },
				layout = vim.fn.winlayout(tabnr),
				sizes = sizes,
				cwd = vim.fn.getcwd(-1, tabnr),
				focus = win,
				tab_focus = vim.api.nvim_tabpage_get_win(tab),
			}
		end,
		desc = "Snapshot closing window for reopen",
	})

	vim.api.nvim_create_autocmd("TabClosed", {
		callback = function()
			local wins, first = {}, nil
			while closed[#closed] and closed[#closed].tab and not vim.api.nvim_tabpage_is_valid(closed[#closed].tab) do
				first = table.remove(closed)
				for id, s in pairs(first.wins) do wins[id] = s end
			end
			if not first then return end
			closed[#closed + 1] = { wins = wins, layout = first.layout, sizes = first.sizes, cwd = first.cwd, focus = first.tab_focus }
		end,
		desc = "Fold the closed tab's windows into one reopen entry",
	})

	function ReopenLastClosed()
		local e = table.remove(closed)
		if not e then return vim.notify("Nothing closed to reopen", vim.log.levels.INFO) end
		if not vim.iter(vim.tbl_values(e.wins)):any(restorable) then
			return vim.notify("Buffers of the last closed " .. (e.tab and "window" or "tab") .. " are gone", vim.log.levels.WARN)
		end

		local spare
		if e.tab then
			assert(vim.api.nvim_tabpage_is_valid(e.tab), "closing a tab folds its windows into a tab entry")
			vim.api.nvim_set_current_tabpage(e.tab)
		else
			vim.cmd.tabnew()
			vim.cmd.tcd(vim.fn.fnameescape(e.cwd))
			vim.bo.bufhidden = "wipe"
			spare = vim.api.nvim_get_current_win()
		end
		local tab = vim.api.nvim_get_current_tabpage()

		local reopened = {}
		local function place(id)
			local s = e.wins[id]
			if not s then return live(id, tab) end
			if not restorable(s) then return end
			local buf = vim.api.nvim_buf_is_valid(s.buf) and s.buf or vim.fn.bufadd(s.path)
			local w = spare or vim.api.nvim_open_win(buf, false, { split = "below", win = -1 })
			spare = nil
			vim.api.nvim_win_set_buf(w, buf)
			vim.bo[buf].buflisted = s.listed
			moved[id] = w
			reopened[w] = s
			return w
		end
		local function prune(node)
			if node[1] == "leaf" then
				local w = place(node[2])
				return w and { "leaf", w }
			end
			local kids = vim.iter(node[2]):map(prune):totable()
			if #kids <= 1 then return kids[1] end
			return { node[1], kids }
		end
		local function first(node)
			while node[1] ~= "leaf" do node = node[2][1] end
			return node[2]
		end
		-- kids are laid out as single windows before recursing, so each split lands in the intended container
		local function arrange(node)
			if node[1] == "leaf" then return end
			for i = 2, #node[2] do
				assert(vim.fn.win_splitmove(first(node[2][i]), first(node[2][i - 1]), { vertical = node[1] == "row", rightbelow = true }) == 0)
			end
			vim.iter(node[2]):each(arrange)
		end
		arrange(prune(e.layout))
		assert(not spare, "at least one window is restorable")

		for _ = 1, 2 do -- each resize shifts its neighbours, as with winrestcmd()
			for id, size in pairs(e.sizes) do
				local w = live(id, tab)
				if w then
					vim.api.nvim_win_set_width(w, size[1])
					vim.api.nvim_win_set_height(w, size[2])
				end
			end
		end
		for w, s in pairs(reopened) do
			vim.api.nvim_win_call(w, function() vim.fn.winrestview(s.view) end)
		end
		local focus = live(e.focus, tab)
		if focus then vim.api.nvim_set_current_win(focus) end
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
