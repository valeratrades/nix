--TODO!: setup when I have the time.Seems amazing
-- https://github.com/kawre/leetcode.nvim
return {
	"kawre/leetcode.nvim",
	build = ":TSUpdate html",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim", -- required by telescope
		"MunifTanjim/nui.nvim",

		-- optional
		"rcarriga/nvim-notify",
		"nvim-tree/nvim-web-devicons",
	},
	opts = {
		---@type lc.domain
		domain = "com", -- For now "com" is the only one supported

		---@type string
		arg = "leetcode.nvim",

		---@type lc.lang
		lang = "cpp",

		---@type lc.sql
		sql = "mysql",

		---@type string
		directory = vim.fn.stdpath("data") .. "/leetcode/",

		---@type boolean
		logging = true,

		console = {
			open_on_runcode = true, ---@type boolean

			dir = "row", ---@type "col" | "row"

			size = {
				width = "90%", ---@type string | integer
				height = "75%", ---@type string | integer
			},

			result = {
				size = "60%", ---@type string | integer
			},

			testcase = {
				virt_text = true, ---@type boolean

				size = "40%", ---@type string | integer
			},
		},

		description = {
			position = "left", ---@type "top" | "right" | "bottom" | "left"

			width = "40%", ---@type string | integer
		},
	},
}
