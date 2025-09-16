require('todo-comments').setup {
	keywords = {
		FIX = {
			icon = " ", -- icon used for the sign, and in search results
			color = "error", -- can be a hex color, or a named color (see below)
			alt = { "FIXME", "BUG", "FIXIT", "ISSUE" }, -- a set of other keywords that all map to this FIX keywords
			-- signs = false, -- configure signs for some keywords individually
		},
		TODO = { icon = " ", color = "#FF8C00", alt = { "TODO", "TODO:", "TODO!:", "TODO!!:", "TODO!!!:", "TODO!!!!:", "TODO!!!!!:", "TODO!!!!!!:", "TODO!!!!!!!:", "TODO!!!!!!!!:", "TODO!!!!!!!!!:", "TODO!!!!!!!!!!:", "TODO!!!!!!!!!!!:", "TODO!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!!!!!:", "TODO!!!!!!!!!!!!!!!!!!!:" } },
		HACK = { icon = " ", color = "warning" },
		WARN = { icon = " ", color = "#BA6E3D", alt = { "WARNING", "XXX" } },
		PERF = { icon = " ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
		Q = { icon = "", color = "hint", alt = { "?", "?:" } },
		TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
	},
}

vim.keymap.set("n", "<Space>sm", "<cmd>TodoTelescope<CR>")

--TODO!: test instance
