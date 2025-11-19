local bufnr = vim.api.nvim_get_current_buf()

-- Guard: check if keymaps are already set up for this buffer
local existing_keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
for _, keymap in ipairs(existing_keymaps) do
	if keymap.lhs == '<Space>re' then
		return -- Already set up, don't re-source
	end
end

-- LspAttach hook to ensure on_attach is called if LSP keymaps aren't set
vim.api.nvim_create_autocmd('LspAttach', {
	buffer = bufnr,
	callback = function(args)
		-- Check if the main LSP keymap is already set
		local has_lsp_keymap = false
		local keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
		for _, keymap in ipairs(keymaps) do
			if keymap.lhs == '<Space>lD' then
				has_lsp_keymap = true
				break
			end
		end

		-- If LSP keymaps aren't set, call on_attach
		if not has_lsp_keymap then
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client then
				require('valera.lsp').on_attach(client, bufnr)
			end
		end
	end,
})

K('n', '<Space>re', function()
	vim.cmd.RustLsp('expandMacro')
end, { desc = "Rustacean: Expand Macro", buffer = bufnr, overwrite = nil })

K('n', '<Space>rb', function()
	vim.cmd.RustLsp('rebuildProcMacros')
end, { desc = "Rustacean: Rebuild Proc Macros", buffer = bufnr, overwrite = nil })

K('n', '<Space>rn', function()
	vim.cmd.RustLsp { 'moveItem', 'up' }
end, { desc = "Rustacean: Move Item Up", buffer = bufnr, overwrite = nil })

K('n', '<Space>rr', function()
	vim.cmd.RustLsp { 'moveItem', 'down' }
end, { desc = "Rustacean: Move Item Down", buffer = bufnr, overwrite = nil })

--?
K('n', '<Space>ra', function()
	vim.cmd.RustLsp('codeAction') -- allegedly, RA sometimes groups suggestions by by category, and vim.lsp.buf.codeAction doesn't support that
end, { desc = "Rustacean: Code Action", buffer = bufnr, overwrite = nil })

K('n', '<Space>rh', function()
	vim.cmd.RustLsp('explainError', 'current') -- default is 'cycle'
end, { desc = "Rustacean: Explain Error", buffer = bufnr, overwrite = nil })

K('n', '<Space>rd', function()
	vim.cmd.RustLsp({ 'renderDiagnostic', 'current' }) -- default is 'cycle'
end, { desc = "Rustacean: Render Diagnostic", buffer = bufnr, overwrite = nil })

K('n', '<Space>rl', function()
		vim.cmd.RustLsp('relatedDiagnostics')
	end,
	{ desc = "Rustacean: Related Diagnostic (for when you break the callsite by changing an object and a hint appears)", buffer = bufnr, overwrite = nil })

K('n', '<Space>rc', function()
	vim.cmd.RustLsp('openCargo')
end, { desc = "Rustacean: Open Cargo", buffer = bufnr, overwrite = nil })

K('n', '<Space>rp', function()
	vim.cmd.RustLsp('parentModule')
end, { desc = "Rustacean: Parent Module", buffer = bufnr, overwrite = nil })

K('n', '<Space>rj', function()
	vim.cmd.RustLsp('joinLines')
end, { desc = "Rustacean: Join Lines", buffer = bufnr, overwrite = nil })

K('n', '<Space>rs', function()
	vim.cmd.RustLsp { 'ssr' } -- requires a query
end, { desc = "Rustacean: Structural Search Replace", buffer = bufnr, overwrite = nil })

K('n', '<Space>rt', function()
	vim.cmd.RustLsp('syntaxTree')
end, { desc = "Rustacean: Syntax Tree", buffer = bufnr, overwrite = nil })

K('n', '<Space>rm', function()
	vim.cmd.RustLsp('view', 'mir')
end, { desc = "Rustacean: View MIR", buffer = bufnr, overwrite = nil })

K('n', '<Space>ri', function()
	vim.cmd.RustLsp('view', 'hir')
end, { desc = "Rustacean: View HIR", buffer = bufnr, overwrite = nil })


--?
--vim.cmd.RustLsp {
--  'workspaceSymbol',
--  '<onlyTypes|allSymbols>' --[[ optional ]],
--  '<query>' --[[ optional ]],
--  bang = true --[[ optional ]]
--}
