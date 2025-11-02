return {
	"nvim-lualine/lualine.nvim",
	dependencies = {
		"nvim-lua/lsp-status.nvim",
	},
	config = function()
		local lsp_status = require('lsp-status')
		local diagnostics = {
			"diagnostics",
			sources = { "nvim_diagnostic" },
			sections = { "error", "warn" },
			symbols = { error = "", warn = "" },
			always_visible = false,
		}
		local function hide_in_width()
			return vim.fn.winwidth(0) > 80
		end

		--local function countSpellingMistakes()
		--	local count = 0
		--	for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		--		for word in line:gmatch("%w+") do
		--			if vim.fn.spellbadword(word)[2] == "bad" then
		--				count = count + 1
		--			end
		--		end
		--	end
		--	return count
		--end
		--local n_misspelled = function()
		--	---@diagnostic disable-next-line: undefined-field
		--	if vim.opt_local.spell:get() == true then
		--		local count = countSpellingMistakes()
		--		return count
		--	else
		--		return ""
		--	end
		--end

		local function diff_source()
			local gitsigns = vim.b.gitsigns_status_dict
			if gitsigns then
				return {
					added = gitsigns.added,
					modified = gitsigns.changed,
					removed = gitsigns.removed,
				}
			end
		end
		local spaces = function()
			return ".." .. vim.api.nvim_get_option_value("shiftwidth", { buf = 0 })
		end
		local location = {
			"location",
			padding = 0,
		}
		----:h lualine-filename-component-options
		--local filename = {
		--	'filename',
		--	path = 1,
		--}
		local diff = {
			"diff",
			symbols = { added = " ", modified = " ", removed = " " },
			cond = hide_in_width,
			source = diff_source,
		}


		require('lualine').setup {
			options = {
				icons_enabled = true,
				theme = 'auto',
				component_separators = { left = '', right = '' },
				section_separators = { left = '', right = '' },
				disabled_filetypes = {
					statusline = {},
					winbar = {},
				},
				ignore_focus = {},
				always_divide_middle = true,
				globalstatus = false,
				refresh = {
					statusline = 1000,
					tabline = 1000,
					winbar = 1000,
				}
			},
			sections = {
				lualine_a = { 'mode' },
				lualine_d = { { "b:gitsigns_head", icon = "" } },
				lualine_b = { diagnostics, --[[n_misspelled]] },
				--TODO!: figure out how to display `example/m.rs` instead of `mod.rs`
				lualine_c = { 'filename' }, -- does repeat one indicated at the top of the tab, but this one has consistent location rel to pane's pos.
				lualine_x = { diff, spaces, 'encoding' },
				lualine_y = { 'progress' },
				lualine_z = { location }
			},
			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = { 'filename' },
				lualine_x = { location },
				lualine_y = {},
				lualine_z = {}
			},
			tabline = {},
			winbar = {},
			inactive_winbar = {},
			extensions = {}
		}
	end,
}
