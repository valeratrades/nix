--NB: to init, the first time must auth with `Copilot auth`
return require "lazier" {
	"zbirenbaum/copilot.lua",
	event = "VeryLazy",
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
			should_attach = function(bufnr)
				return not vim.g.copilot_kill
			end,
		})

		vim.api.nvim_create_user_command("CopilotToggle", function()
			vim.g.copilot_kill = not vim.g.copilot_kill
			if vim.g.copilot_kill then
				-- detach from all buffers and dismiss any visible suggestion
				pcall(function() require('copilot.suggestion').dismiss() end)
				local client = require('copilot.client').get()
				if client then
					for _, buf in ipairs(vim.api.nvim_list_bufs()) do
						if vim.lsp.buf_is_attached(buf, client.id) then
							vim.lsp.buf_detach_client(buf, client.id)
						end
					end
				end
				print("Copilot: OFF")
			else
				-- re-attach to current buffer (others will attach via should_attach on BufEnter)
				local client = require('copilot.client').get()
				if client then
					local buf = vim.api.nvim_get_current_buf()
					if not vim.lsp.buf_is_attached(buf, client.id) then
						vim.lsp.buf_attach_client(buf, client.id)
					end
				end
				print("Copilot: ON")
			end
		end, {})
	end,
}
