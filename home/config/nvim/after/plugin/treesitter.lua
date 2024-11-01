vim.g.maplocalleader = "\\"

require('nvim-treesitter.configs').setup {
	ensure_installed = { "c", "cpp", "lua", "rust", "go", "python", "javascript", "typescript", "gitignore", "markdown", "mermaid", "typst", "awk" },
	sync_install = true,
	auto_install = true,
	indent = { enable = true },
	highlight = {
		enable = true,
		additional_vim_regex_highlighting = true, -- highlight TODOs for example
	},
	-- autopairs = {
	--  enable = true,
	--},
	autotag = { -- html tags
		enable = true,
	},
	incremental_selection = {
		enable = true,
		keymaps = {
			--init_selection = "\\s",
			node_incremental = "\\s",
			scope_incremental = false,
			node_decremental = "\\t",
		},
	},
	textobjects = {
		move = {
			enable = true,
			set_jumps = false, -- whether to set jumps in the jumplist
			goto_next_start = {
				["]m"] = "@function.outer",
				["]]"] = "@class.outer",
				["]o"] = "@loop.*",
				["]s"] = { query = "@scope", query_group = "locals", desc = "Next scope" },
				["]z"] = { query = "@fold", query_group = "folds", desc = "Next fold" },
			},
			goto_next_end = {
				["]M"] = "@function.outer",
				["]["] = "@class.outer",
			},
			goto_previous_start = {
				["[m"] = "@function.outer",
				["[["] = "@class.outer",
			},
			goto_previous_end = {
				["[M"] = "@function.outer",
				["[]"] = "@class.outer",
			},
			goto_next = {
				["]d"] = "@conditional.outer",
			},
			goto_previous = {
				["[d"] = "@conditional.outer",
			},
		},
		select = {
			enable = true,
			lookahead = true,
			keymaps = {
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
				["aa"] = "@parameter.outer",
				["ia"] = "@parameter.inner",
			},
		},
		swap = {
			enable = true,
			swap_previous = {
				["g<"] = "@parameter.inner",
			},
			swap_next = {
				["g>"] = "@parameter.inner",
			},
		},
		lsp_interop = {
			enable = true,
			border = 'none',
			lookahead = true,
			floating_preview_opts = {},
			peek_definition_code = {
				["\\f"] = "@function.inner",
				["\\c"] = "@class.inner",
			},
		},
	},
}

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
