--NB: to init, the first time must auth with `Copilot auth`
return require "lazier" {
	"zbirenbaum/copilot.lua",
	dependencies = {
		"copilotlsp-nvim/copilot-lsp", -- (optional) for NES functionality
	},
	config = function()
		local lsp_mod = require("valera.lsp")

		require('copilot').setup({
			--nes = {
			--	enabled = true,
			--},
			server_opts_overrides = {
				offset_encoding = lsp_mod.get_preferred_encoding(),
			},
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
		})
	end,
}
