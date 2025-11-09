return require "lazier" {
	"folke/trouble.nvim",
	opts = {
		modes = {
			symbols = {
				--auto_open = true, -- behaves inconsistently, have to do manually
				--auto_close = true, -- without `auto_open`, just nukes itself when navigating
				auto_refresh = true,
				warn_no_results = false,
				pinned = false, -- don't pin to initial window (doesn't work)
				focus = false, -- don't focus on open
			},
		},
	},
	cmd = "Trouble",
	keys = {
		{
			"<space><space>x",
			"<cmd>Trouble symbols close<cr><cmd>Trouble symbols open<cr>", --HACK: with current impl it's pinned to the window. So if I need it in another one - must first close. (2025/06/06)
			desc = "Symbols (Trouble)",
		},
	},
}
