vim.keymap.set('n', '<Space>re', function()
	vim.cmd.RustLsp('expandMacro')
end, { desc = "Rustacean: Expand Macro" })

vim.keymap.set('n', '<Space>rb', function()
	vim.cmd.RustLsp('rebuildProcMacros')
end, { desc = "Rustacean: Rebuild Proc Macros" })

vim.keymap.set('n', '<Space>rn', function()
	vim.cmd.RustLsp { 'moveItem', 'up' }
end, { desc = "Rustacean: Move Item Up" })

vim.keymap.set('n', '<Space>rr', function()
	vim.cmd.RustLsp { 'moveItem', 'down' }
end, { desc = "Rustacean: Move Item Down" })

--?
vim.keymap.set('n', '<Space>ra', function()
	vim.cmd.RustLsp('codeAction') -- allegedly, RA sometimes groups suggestions by by category, and vim.lsp.buf.codeAction doesn't support that
end, { desc = "Rustacean: Code Action" })

vim.keymap.set('n', '<Space>rh', function()
	vim.cmd.RustLsp('explainError', 'current') -- default is 'cycle'
end, { desc = "Rustacean: Explain Error" })

vim.keymap.set('n', '<Space>rd', function()
	vim.cmd.RustLsp({ 'renderDiagnostic', 'current' }) -- default is 'cycle'
end, { desc = "Rustacean: Render Diagnostic" })

vim.keymap.set('n', '<Space>rc', function()
	vim.cmd.RustLsp('openCargo')
end, { desc = "Rustacean: Open Cargo" })

vim.keymap.set('n', '<Space>rp', function()
	vim.cmd.RustLsp('parentModule')
end, { desc = "Rustacean: Parent Module" })

vim.keymap.set('n', '<Space>rj', function()
	vim.cmd.RustLsp('joinLines')
end, { desc = "Rustacean: Join Lines" })

vim.keymap.set('n', '<Space>rs', function()
	vim.cmd.RustLsp { 'ssr' } -- requires a query
end, { desc = "Rustacean: Structural Search Replace" })

vim.keymap.set('n', '<Space>rt', function()
	vim.cmd.RustLsp('syntaxTree')
end, { desc = "Rustacean: Syntax Tree" })

vim.keymap.set('n', '<Space>rm', function()
	vim.cmd.RustLsp('view', 'mir')
end, { desc = "Rustacean: View MIR" })

vim.keymap.set('n', '<Space>ri', function()
	vim.cmd.RustLsp('view', 'hir')
end, { desc = "Rustacean: View HIR" })

--?
--vim.cmd.RustLsp {
--  'workspaceSymbol',
--  '<onlyTypes|allSymbols>' --[[ optional ]],
--  '<query>' --[[ optional ]],
--  bang = true --[[ optional ]]
--}
