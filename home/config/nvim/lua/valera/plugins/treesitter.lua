return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	dependencies = {
		{ "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
		"nvim-treesitter/nvim-treesitter-context",
	},
	config = function()
		require('nvim-treesitter').setup {
			auto_install = true,
		}

		-- textobjects
		local select = require 'nvim-treesitter-textobjects.select'
		local move = require 'nvim-treesitter-textobjects.move'
		local swap = require 'nvim-treesitter-textobjects.swap'

		require('nvim-treesitter-textobjects').setup {
			select = {
				lookahead = true, -- automatically jump forward to textobj, similar to targets.vim
			},
			move = {
				set_jumps = false, -- whether to set jumps in the jumplist
			},
		}

		-- select
		for _, mapping in ipairs {
			{ "af", "@function.outer" },
			{ "if", "@function.inner" },
			{ "ac", "@class.outer" },
			{ "ic", "@class.inner" },
			{ "aa", "@parameter.outer" },
			{ "ia", "@parameter.inner" },
		} do
			vim.keymap.set({ "x", "o" }, mapping[1], function()
				select.select_textobject(mapping[2], "textobjects")
			end)
		end

		-- move
		for _, mapping in ipairs {
			{ "]m", "goto_next_start", "@function.outer" },
			{ "]]", "goto_next_start", "@class.outer" },
			{ "]o", "goto_next_start", { "@loop.inner", "@loop.outer" } },
			{ "]s", "goto_next_start", "@local.scope", "locals" },
			{ "]z", "goto_next_start", "@fold", "folds" },
			{ "]M", "goto_next_end", "@function.outer" },
			{ "][", "goto_next_end", "@class.outer" },
			{ "[m", "goto_previous_start", "@function.outer" },
			{ "[[", "goto_previous_start", "@class.outer" },
			{ "[M", "goto_previous_end", "@function.outer" },
			{ "[]", "goto_previous_end", "@class.outer" },
			{ "]d", "goto_next", "@conditional.outer" },
			{ "[d", "goto_previous", "@conditional.outer" },
		} do
			local query_group = mapping[4] or "textobjects"
			vim.keymap.set({ "n", "x", "o" }, mapping[1], function()
				move[mapping[2]](mapping[3], query_group)
			end)
		end

		-- swap
		vim.keymap.set("n", "g<", function()
			swap.swap_previous("@parameter.inner")
		end)
		vim.keymap.set("n", "g>", function()
			swap.swap_next("@parameter.inner")
		end)

		-- incremental selection: removed from nvim-treesitter main.
		-- \\s / \\t bindings were: init/increment/decrement node selection.
		--TODO: find a replacement plugin or implement manually via vim.treesitter.get_node()

		-- context
		require 'treesitter-context'.setup {
			enable = true,          -- Enable this plugin (Can be enabled/disabled later via commands)
			max_lines = 0,          -- How many lines the window should span. Values <= 0 mean no limit.
			min_window_height = 20, -- Minimum editor window height to enable context. Values <= 0 mean no limit.
			line_numbers = true,
			multiline_threshold = 1, -- Maximum number of lines to show for a single context
			trim_scope = 'outer',   -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
			mode = 'cursor',        -- Line used to calculate context. Choices: 'cursor', 'topline'
			-- Separator between context and content. Should be a single character string, like '-'.
			-- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
			separator = nil,
			zindex = 20,    -- The Z-index of the context window
			on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
		}
	end,
}
