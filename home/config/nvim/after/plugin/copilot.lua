require('copilot').setup({
	panel = {
		enabled = true,
		auto_refresh = false,
		keymap = {
			jump_prev = "[[",
			jump_next = "]]",
			accept = "<CR>",
			refresh = "gr",
			open = "<M-CR>"
		},
		layout = {
			position = "bottom", -- | top | left | right
			ratio = 0.4
		},
	},
	suggestion = {
		enabled = true,
		auto_trigger = true,
		hide_during_completion = false,
		debounce = 0,
		keymap = {
			accept = "<Right>",
			accept_word = "<Left>",
			accept_line = "<M-k>",
			next = "<M-]>",
			prev = "<M-[>",
			dismiss = "<C-]>",
		},
	},
	filetypes = {
		markdown = false,
		latex = false,
		typst = false,
		text = false,

		help = false,
		gitcommit = false,
		gitrebase = false,
		hgcommit = false,

		svn = false,
		cvs = false,
		yaml = false,
		json = false,
		yuck = false,
		toml = false,
	},
	copilot_node_command = 'node', -- Node.js version must be > 18.x
	server_opts_overrides = {},
})

--K("i", "<Tab>", "<Tab>") // needed this with old copilot.vim, leave here until certain that it's not needed anymore
