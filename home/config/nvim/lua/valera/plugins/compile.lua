return require "lazier" {
	'ej-shafran/compile-mode.nvim',
	version = '^5.0.0',
	lazy = false,
	dependencies = {
		'nvim-lua/plenary.nvim',
	},
	config = function()
		---@type CompileModeOpts
		vim.g.compile_mode = {
			default_command = '',
			baleia_setup = false,
			bang_expansion = false,
			error_regexp_table = {},
			error_ignore_file_list = {},
			error_threshold = require('compile-mode').level.WARNING,
			auto_jump_to_first_error = false,
			error_locus_highlight = 500,
			use_diagnostics = true,
			recompile_no_fail = false,
			ask_about_save = true,
			ask_to_interrupt = true,
			buffer_name = '*compilation*',
			time_format = '%a %b %e %H:%M:%S',
			hidden_output = {},
			environment = nil,
			clear_environment = false,
			input_word_completion = false,
			hidden_buffer = false,
			focus_compilation_buffer = false,
			use_circular_error_navigation = false,
			debug = false,
		}

		local compile_mode = require 'compile-mode'
		K('n', '<space>cc', ':Compile<CR>', { desc = '[C]ompile [C]ommand' })
		K('n', '<space>cC', compile_mode.close_buffer, { desc = '[C]ompile [C]lose buffer' })
		K('n', '<space>cq', compile_mode.send_to_qflist, { desc = '[C]ompile to [Q]uickfix' })
	end,
}
