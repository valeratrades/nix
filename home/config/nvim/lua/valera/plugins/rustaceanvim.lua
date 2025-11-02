return {
	'mrcjkb/rustaceanvim',
	lazy = false, -- This plugin is already lazy
	ft = 'rust',
	config = function()
		K('n', '<Space>re', function()
			vim.cmd.RustLsp('expandMacro')
		end, { desc = "Rustacean: Expand Macro" })

		K('n', '<Space>rb', function()
			vim.cmd.RustLsp('rebuildProcMacros')
		end, { desc = "Rustacean: Rebuild Proc Macros" })

		K('n', '<Space>rn', function()
			vim.cmd.RustLsp { 'moveItem', 'up' }
		end, { desc = "Rustacean: Move Item Up" })

		K('n', '<Space>rr', function()
			vim.cmd.RustLsp { 'moveItem', 'down' }
		end, { desc = "Rustacean: Move Item Down" })

		--?
		K('n', '<Space>ra', function()
			vim.cmd.RustLsp('codeAction') -- allegedly, RA sometimes groups suggestions by by category, and vim.lsp.buf.codeAction doesn't support that
		end, { desc = "Rustacean: Code Action" })

		K('n', '<Space>rh', function()
			vim.cmd.RustLsp('explainError', 'current') -- default is 'cycle'
		end, { desc = "Rustacean: Explain Error" })

		K('n', '<Space>rd', function()
			vim.cmd.RustLsp({ 'renderDiagnostic', 'current' }) -- default is 'cycle'
		end, { desc = "Rustacean: Render Diagnostic" })

		K('n', '<Space>rl', function()
			vim.cmd.RustLsp('relatedDiagnostics')
		end,
			{ desc = "Rustacean: Related Diagnostic (for when you break the callsite by changing an object and a hint appears)" })

		K('n', '<Space>rc', function()
			vim.cmd.RustLsp('openCargo')
		end, { desc = "Rustacean: Open Cargo" })

		K('n', '<Space>rp', function()
			vim.cmd.RustLsp('parentModule')
		end, { desc = "Rustacean: Parent Module" })

		K('n', '<Space>rj', function()
			vim.cmd.RustLsp('joinLines')
		end, { desc = "Rustacean: Join Lines" })

		K('n', '<Space>rs', function()
			vim.cmd.RustLsp { 'ssr' } -- requires a query
		end, { desc = "Rustacean: Structural Search Replace" })

		K('n', '<Space>rt', function()
			vim.cmd.RustLsp('syntaxTree')
		end, { desc = "Rustacean: Syntax Tree" })

		K('n', '<Space>rm', function()
			vim.cmd.RustLsp('view', 'mir')
		end, { desc = "Rustacean: View MIR" })

		K('n', '<Space>ri', function()
			vim.cmd.RustLsp('view', 'hir')
		end, { desc = "Rustacean: View HIR" })


		--?
		--vim.cmd.RustLsp {
		--  'workspaceSymbol',
		--  '<onlyTypes|allSymbols>' --[[ optional ]],
		--  '<query>' --[[ optional ]],
		--  bang = true --[[ optional ]]
		--}
	end
}
