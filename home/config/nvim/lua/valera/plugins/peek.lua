return require "lazier" {
	"toppair/peek.nvim",
	event = { "VeryLazy" },
	build = "deno task --quiet build:fast",
	config = function()
		require('peek').setup({
			auto_load = false,      -- whether to automatically load preview when
			-- entering another markdown buffer
			close_on_bdelete = true, -- close preview window on buffer delete

			syntax = true,          -- enable syntax highlighting, affects performance

			update_on_change = true,

			app = 'webview',          -- 'webview', 'browser', string or a table of strings

			filetype = { 'markdown' }, -- list of filetypes to recognize as markdown

			-- relevant if update_on_change is true
			throttle_at = 200000,  -- start throttling when file exceeds this
			-- amount of bytes in size
			throttle_time = 'auto', -- minimum amount of time in milliseconds
			-- that has to pass before starting new render
		})

		local peek = require("peek")
		vim.api.nvim_create_user_command("PeekOpen", function() peek.open() end, {})
		vim.api.nvim_create_user_command("PeekClose", function() peek.close() end, {})
	end
}
