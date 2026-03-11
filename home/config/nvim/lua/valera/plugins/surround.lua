return require "lazier" {
	"kylechui/nvim-surround",
	version = "*",
	event = "VeryLazy",
	init = function()
		vim.g.nvim_surround_no_mappings = true
	end,
	config = function()
		require("nvim-surround").setup({})

		K("n", "ys", "<Plug>(nvim-surround-normal)", { desc = "Surround add" })
		K("n", "ds", "<Plug>(nvim-surround-delete)", { desc = "Surround delete" })
		K("n", "cs", "<Plug>(nvim-surround-change)", { desc = "Surround change" })
		K("x", "S", "<Plug>(nvim-surround-visual)", { desc = "Surround visual" })

		--TODO!: add functionality for interpreting things like `Option<>` and `Result<>` as singular surrounding construct.
		-- Could use: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
	end
}
