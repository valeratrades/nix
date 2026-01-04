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

-- Just don't see a point, given I'm always visually selecting first (which is the right practice)
---- Highlight Yanked Text
--vim.api.nvim_create_autocmd({ "TextYankPost" }, {
--	callback = function()
--		vim.highlight.on_yank({ higroup = "Visual", timeout = 200 })
--	end,
--})

-- Disable undo file for .env files
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
	pattern = { "*.env" },
	callback = function()
		vim.opt_local.undofile = false
	end,
})

-- it messing with comments outweighs all the potential benefits of having it on
--vim.api.nvim_create_autocmd({ "BufWrite" }, {
--	pattern = { "python" },
--	callback = function()
--		vim.lsp.buf.format { async = true }
--	end,
--})
