return require "lazier" {
	"nvim-neotest/neotest",
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
