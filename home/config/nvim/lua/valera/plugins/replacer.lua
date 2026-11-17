return {
	'gabrielpoca/replacer.nvim',
	opts = {
		rename_files = false,
		save_on_write = true,
	},
	keys = {
		{
			'<space>h',
			function() require('replacer').run() end,
			desc = "run replacer.nvim"
		}
	},
	config = function(_, opts)
		require('replacer').setup(opts)

		-- Add keybinding to jump to location from replacer buffer
		-- Use BufEnter with a slight delay to ensure we override replacer's mappings
		vim.api.nvim_create_autocmd({'FileType', 'BufEnter'}, {
			pattern = 'qf',
			callback = function(ev)
				vim.defer_fn(function()
					K('n', '<CR>', function()
						local line = vim.fn.line('.')
						vim.cmd('cc ' .. line)
					end, { buffer = ev.buf, desc = "Jump to quickfix location", overwrite = true })
				end, 10)
			end
		})
	end
}
