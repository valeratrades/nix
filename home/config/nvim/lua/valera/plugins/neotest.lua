return require "lazier" {
	"nvim-neotest/neotest",
	-- Its config `require`s the rustaceanvim adapter, which snapshots `vim.g.rustaceanvim`.
	-- At startup that snapshot would be taken before valera.lsp assigns the global.
	event = "VeryLazy",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter"
	},
	config = function()
		----TODO!!!: setup
		require('neotest').setup {
			-- ...,
			adapters = {
				-- ...,
				require('rustaceanvim.neotest'),
				--require("neotest-python")({
				--	dap = { justMyCode = false },
				--}),
				--require("neotest-plenary"),
				--require("neotest-vim-test")({
				--	ignore_file_types = { "python", "vim", "lua", "rust" },
				--}),
			},
		}
	end
}
