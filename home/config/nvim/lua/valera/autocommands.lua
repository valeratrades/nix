vim.cmd [[
  au BufWinLeave * silent! mkview
  au BufWinEnter * silent! loadview
  autocmd FileType * :set formatoptions-=ro
	autocmd VimEnter,WinNew,BufWinEnter * lua vim.fn.chdir(vim.env.PWD)
	autocmd BufRead,BufNewFile *.md set conceallevel=3
	autocmd BufRead,BufNewFile *.txt set conceallevel=3
]]


vim.api.nvim_create_autocmd({ "FileType" }, {
	pattern = { "lean", "yaml", "yml" },
	callback = function()
		vim.opt_local.expandtab = true
	end,
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

vim.api.nvim_create_autocmd({ "BufWrite" }, {
	pattern = { "python" },
	callback = function()
		vim.lsp.buf.format { async = true }
	end,
})
