vim.cmd [[
  au BufWinLeave * silent! mkview
  au BufWinEnter * silent! loadview
  autocmd FileType * :set formatoptions-=ro
	autocmd VimEnter,WinNew,BufWinEnter * lua vim.fn.chdir(vim.env.PWD)
	"autocmd BufRead,BufNewFile *.md set conceallevel=3
	"autocmd BufRead,BufNewFile *.txt set conceallevel=3
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

--HACK: this is the workaround to have true `auto_open` on the `Trouble` plugin, across the tabs
vim.api.nvim_create_autocmd("TabEnter", {
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local n = 0
    for _, client in pairs(vim.lsp.get_clients()) do
      if client.name ~= "copilot" and client.attached_buffers and client.attached_buffers[bufnr] then
        n = n + 1
      end
    end
    if n > 0 then
			vim.cmd('Trouble symbols close')
			vim.cmd('Trouble symbols open')
			vim.defer_fn(function()
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>=", true, false, true), "n", false)
			end, 20) -- window doesn't open instantly
    end
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
