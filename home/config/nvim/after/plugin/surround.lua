require("nvim-surround").setup({
	keymaps = {
		insert = false,
		insert_line = false,
		normal = "ys",
		normal_cur = false,
		normal_line = false,
		normal_cur_line = false,
		visual = "S",
		visual_line = false,
		delete = "ds",
		change = "cs",
	}
})

--TODO!: add functionality for interpreting things like `Option<>` and `Result<>` as singular surrounding construct.
-- Could use: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
