-- Files like `foo.rslike` or `foo.rs.bak` get treesitter highlighting
-- for the corresponding language, but no LSP attaches.

-- Map extensions to treesitter parsers
local lang_map = {
	rs = "rust",
	rust = "rust",
	py = "python",
	python = "python",
	lua = "lua",
	js = "javascript",
	ts = "typescript",
	go = "go",
	c = "c",
	cpp = "cpp",
	zig = "zig",
	nix = "nix",
	toml = "toml",
	json = "json",
	yaml = "yaml",
	yml = "yaml",
	md = "markdown",
	sh = "bash",
	bash = "bash",
}

vim.filetype.add({
	pattern = {
		-- Match *.xyzlike (e.g., foo.rslike, bar.content.rustlike)
		[".*like"] = function(path, bufnr)
			local lang = path:match("%.(%w+)like$")
			if lang and lang_map[lang] then
				return lang .. "like"
			end
		end,
		-- Match *.xyz.bak (e.g., foo.rs.bak, bar.py.bak)
		[".*%.bak"] = function(path, bufnr)
			local lang = path:match("%.(%w+)%.bak$")
			if lang and lang_map[lang] then
				return lang .. ".bak"
			end
		end,
	},
})

-- Register treesitter parsers for *like and *bak filetypes
for ext, parser in pairs(lang_map) do
	vim.treesitter.language.register(parser, ext .. "like")
	vim.treesitter.language.register(parser, ext .. ".bak")
end

-- Prevent LSP from attaching to .bak files
vim.api.nvim_create_autocmd("LspAttach", {
	pattern = "*.bak",
	callback = function(args)
		vim.schedule(function()
			local clients = vim.lsp.get_clients({ bufnr = args.buf })
			for _, client in ipairs(clients) do
				vim.lsp.buf_detach_client(args.buf, client.id)
			end
		end)
	end,
})
