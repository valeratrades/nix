return {
	'fei6409/log-highlight.nvim',
	config = function()
		require('log-highlight').setup {
			extension = { "log", "window" },
		}
	end,
}
