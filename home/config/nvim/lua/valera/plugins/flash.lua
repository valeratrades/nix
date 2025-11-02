return {
	"folke/flash.nvim",
	event = "VeryLazy",
	---@type Flash.Config
	opts = {
		modes = {
			char = {
				enabled = false,
			},
		},
		labels = 'abcdefghijklmnopqrstuvwxyz',
	},
	jump = {
		pos = 'range', ---@type "start" | "end" | "range"
		autojump = true, -- automatically jump when there is only one match
	},
	-- tylua: ignore
	keys = {
		{ "<space>x", mode = { "n", "x", "o" }, function() require("flash").jump() end,       desc = "Flash" },
		{ "<space>X", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
	},
}
