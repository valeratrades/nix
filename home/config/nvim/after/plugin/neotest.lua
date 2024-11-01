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
