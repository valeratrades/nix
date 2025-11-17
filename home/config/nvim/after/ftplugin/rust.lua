local bufnr = vim.api.nvim_get_current_buf()

K('n', '<Space>re', function()
	vim.cmd.RustLsp('expandMacro')
end, { desc = "Rustacean: Expand Macro", buffer = bufnr })

K('n', '<Space>rb', function()
	vim.cmd.RustLsp('rebuildProcMacros')
end, { desc = "Rustacean: Rebuild Proc Macros", buffer = bufnr })

K('n', '<Space>rn', function()
	vim.cmd.RustLsp { 'moveItem', 'up' }
end, { desc = "Rustacean: Move Item Up", buffer = bufnr })

K('n', '<Space>rr', function()
	vim.cmd.RustLsp { 'moveItem', 'down' }
end, { desc = "Rustacean: Move Item Down", buffer = bufnr })

--?
K('n', '<Space>ra', function()
	vim.cmd.RustLsp('codeAction') -- allegedly, RA sometimes groups suggestions by by category, and vim.lsp.buf.codeAction doesn't support that
end, { desc = "Rustacean: Code Action", buffer = bufnr })

K('n', '<Space>rh', function()
	vim.cmd.RustLsp('explainError', 'current') -- default is 'cycle'
end, { desc = "Rustacean: Explain Error", buffer = bufnr })

K('n', '<Space>rd', function()
	vim.cmd.RustLsp({ 'renderDiagnostic', 'current' }) -- default is 'cycle'
end, { desc = "Rustacean: Render Diagnostic", buffer = bufnr })

K('n', '<Space>rl', function()
	vim.cmd.RustLsp('relatedDiagnostics')
end,
	{ desc = "Rustacean: Related Diagnostic (for when you break the callsite by changing an object and a hint appears)", buffer = bufnr })

K('n', '<Space>rc', function()
	vim.cmd.RustLsp('openCargo')
end, { desc = "Rustacean: Open Cargo", buffer = bufnr })

K('n', '<Space>rp', function()
	vim.cmd.RustLsp('parentModule')
end, { desc = "Rustacean: Parent Module", buffer = bufnr })

K('n', '<Space>rj', function()
	vim.cmd.RustLsp('joinLines')
end, { desc = "Rustacean: Join Lines", buffer = bufnr })

K('n', '<Space>rs', function()
	vim.cmd.RustLsp { 'ssr' } -- requires a query
end, { desc = "Rustacean: Structural Search Replace", buffer = bufnr })

K('n', '<Space>rt', function()
	vim.cmd.RustLsp('syntaxTree')
end, { desc = "Rustacean: Syntax Tree", buffer = bufnr })

K('n', '<Space>rm', function()
	vim.cmd.RustLsp('view', 'mir')
end, { desc = "Rustacean: View MIR", buffer = bufnr })

K('n', '<Space>ri', function()
	vim.cmd.RustLsp('view', 'hir')
end, { desc = "Rustacean: View HIR", buffer = bufnr })


--?
--vim.cmd.RustLsp {
--  'workspaceSymbol',
--  '<onlyTypes|allSymbols>' --[[ optional ]],
--  '<query>' --[[ optional ]],
--  bang = true --[[ optional ]]
--}
