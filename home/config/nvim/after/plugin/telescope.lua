local builtin = require('telescope.builtin')
local actions = require('telescope.actions')
local gs = { hidden = true, no_ignore = true, file_ignore_patterns = { ".git/", "target/", "%.lock" } } -- `^` and `.` in file ignore patterns don't really work

vim.keymap.set('n', '<space>f', function() builtin.find_files(gs) end, { desc = "Search files" })
vim.keymap.set('n', '<space>z', function() builtin.live_grep(gs) end, { desc = "Live grep" })
vim.keymap.set({ 'n', 'v' }, '<space>ss', function() builtin.grep_string(gs) end,
	{ desc = "Grep visual selection or word under cursor" })
vim.keymap.set('n', '<space>sk', function() builtin.keymaps(gs) end, { desc = "Keymaps" })
vim.keymap.set('n', '<space>sg', function() builtin.git_files(gs) end, { desc = "Git files" })
vim.keymap.set('n', '<space>sp', "<cmd>Telescope persisted<cr>", { desc = "Persisted: sessions" })
vim.keymap.set('n', '<space>sb', function() builtin.buffers(gs) end, { desc = "Find buffers" })
vim.keymap.set('n', '<space>sh', function() builtin.help_tags(gs) end, { desc = "Neovim documentation" })
vim.keymap.set('n', '<space>sl', function() builtin.loclist(gs) end, { desc = "Telescope loclist" })
vim.keymap.set('n', '<space>sn', function() builtin.find_files({ hidden = true, no_ignore_parent = true }) end,
	{ desc = "No_ignore_parent" })
vim.keymap.set('n', '<space>st', function()
	FindTodo()
	require('telescope.builtin').quickfix({ wrap_results = true, fname_width = 999 })
end, { desc = "Project's TODOs" })
vim.keymap.set('n', '<space>si', "<cmd>Telescope media_files<cr>", { desc = "Media files" })
vim.keymap.set("n", "<C-f>", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { desc = "Effectively Ctrl+f" })

local telescope = require("telescope")
--FUCK: requires to explicitly:
--```sh
--cd $XDG_DATA_HOME/nvim/lazy/telescope-fzf-native.nvim
--make
--```
telescope.load_extension('fzf')
local fzf_opts = {
	fuzzy = true,                  -- false will only do exact matching
	override_generic_sorter = true, -- override the generic sorter
	override_file_sorter = true,   -- override the file sorter
	case_mode = "smart_case",      -- or "ignore_case" or "respect_case"
}

telescope.setup {
	pickers = {
		lsp_dynamic_workspace_symbols = {
			sorter = telescope.extensions.fzf.native_fzf_sorter(fzf_opts)
		},
	},
	extensions = {
		media_files = {
			filetypes = { "png", "webp", "jpg", "jpeg" },
			find_cmd = "rg"
		},
		--["ui-select"] = {
		--	require("telescope.themes").get_dropdown {
		--		-- even more opts
		--	}
		--
		--	-- pseudo code / specification for writing custom displays, like the one
		--	-- for "codeactions"
		--	-- specific_opts = {
		--	--   [kind] = {
		--	--     make_indexed = function(items) -> indexed_items, width,
		--	--     make_displayer = function(widths) -> displayer
		--	--     make_display = function(displayer) -> function(e)
		--	--     make_ordinal = function(e) -> string
		--	--   },
		--	--   -- for example to disable the custom builtin "codeactions" display
		--	--      do the following
		--	--   codeactions = false,
		--	-- }
		--},
	},
	defaults = {
		mappings = {
			--Can't find action.top there, could this be done?
			i = {
				--TODO!!!: figure out how to do/immitate actions.top
				["<CR>"] = actions.select_default + actions.center,
				["<C-x>"] = actions.select_horizontal + actions.center,
				["<C-v>"] = actions.select_vertical + actions.center,
				["<C-t>"] = actions.select_tab + actions.center,
				["<C-l>"] = actions.select_all + actions.add_selected_to_loclist,
				["<c-f>"] = actions.to_fuzzy_refine,
			},
			n = {
				["<CR>"] = actions.select_default + actions.center,
				["<C-x>"] = actions.select_horizontal + actions.center,
				["<C-v>"] = actions.select_vertical + actions.center,
				["<C-t>"] = actions.select_tab + actions.center,
				["<C-l>"] = actions.select_all + actions.add_selected_to_loclist
			}
		},
		layout_config = {
			width = 9999,
			height = 9999,
		}
	},
}
--
-- Must be loaded strictly _after_ setup
require("telescope").load_extension("media_files")
require("telescope").load_extension("ui-select")

-- Default mappings reference {{{
--<C-n>/<Down>	Next item
--<C-p>/<Up>	Previous item
--j/k	Next/previous (in normal mode)
--<cr>	Confirm selection
--<C-q>	Confirm selection and open quickfix window
--<C-x>	Go to file selection as a split
--<C-v>	Go to file selection as a vsplit
--<C-t>	Go to a file in a new tab
--<C-u>	Scroll up in preview window
--<C-d>	Scroll down in preview window
--<C-/>/?	Show picker mappings (in insert & normal mode, respectively)
--<C-c>	Close telescope
--<Esc>	Close telescope (in normal mode)
-- }}}
