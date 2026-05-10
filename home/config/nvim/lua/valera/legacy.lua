-- Restore old command names removed by upstream

-- `:LspInfo` was removed from nvim-lspconfig (nvim 0.11+).
-- The replacement is `:checkhealth vim.lsp`.
vim.api.nvim_create_user_command("LspInfo", function()
	vim.cmd("checkhealth vim.lsp")
end, { desc = "legacy alias for :checkhealth vim.lsp" })

local function client_name_complete()
	return vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients())
end

-- `:LspStop [name]` — stop all clients, or just the named one(s).
vim.api.nvim_create_user_command("LspStop", function(opts)
	local name = opts.args ~= "" and opts.args or nil
	for _, c in ipairs(vim.lsp.get_clients({ name = name })) do
		c:stop()
	end
end, {
	nargs = "?",
	complete = client_name_complete,
	desc = "Stop LSP clients (optionally filter by name)",
})

-- `:LspFormatters` — list attached clients and whether each advertises
-- document / range formatting. Useful for figuring out who's auto-formatting
-- the current buffer on save.
vim.api.nvim_create_user_command("LspFormatters", function()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then
		print("no LSP clients attached to current buffer")
		return
	end
	local lines = { string.format("%-20s %-8s %-10s", "client", "format", "range_fmt") }
	for _, c in ipairs(clients) do
		table.insert(lines, string.format(
			"%-20s %-8s %-10s",
			c.name,
			tostring(c.server_capabilities.documentFormattingProvider ~= nil
				and c.server_capabilities.documentFormattingProvider ~= false),
			tostring(c.server_capabilities.documentRangeFormattingProvider ~= nil
				and c.server_capabilities.documentRangeFormattingProvider ~= false)
		))
	end
	print(table.concat(lines, "\n"))
end, { desc = "list LSP clients on current buffer with their formatting capabilities" })

-- `:LspRestart [name]` — stop matching clients, then re-edit to reattach.
vim.api.nvim_create_user_command("LspRestart", function(opts)
	local name = opts.args ~= "" and opts.args or nil
	for _, c in ipairs(vim.lsp.get_clients({ name = name })) do
		c:stop()
	end
	vim.defer_fn(function() vim.cmd("e") end, 100)
end, {
	nargs = "?",
	complete = client_name_complete,
	desc = "Restart LSP clients (optionally filter by name)",
})
