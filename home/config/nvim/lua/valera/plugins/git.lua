return {
	require "lazier" {
		"lewis6991/gitsigns.nvim",
		config = function()
			local gs = require("gitsigns")
			gs.setup({
				signs = {
					add          = { text = '│' },
					change       = { text = '│' },
					delete       = { text = '_' },
					topdelete    = { text = '‾' },
					changedelete = { text = '~' },
					untracked    = { text = '┆' },
				},
				max_file_length = 40000,
				numhl = false,
				on_attach = function(bufnr)
					local ft = vim.bo[bufnr].filetype
					if ft == "oil" then
						return false
					end
				end,
			})

			K('n', '<Space>gg', "<cmd>!git add -A && git commit -m '_' && git push<cr><cr>",
				{ desc = "Git: just push", silent = true })
			K('n', '<Space>gp', "<cmd>!git pull<cr><cr>", { desc = "Git: pull", silent = true })
			K('n', '<Space>gr', "<cmd>!git reset --hard<cr><cr>", { desc = "Git: reset --hard", silent = true })
			-- this assumes we correctly did `vim.fn.chdir(vim.env.PWD)` in an autocmd earlier. Otherwise this will often try to execute commands one level in the filetree above.
			K('n', '<Space>gd', gs.diffthis, { desc = "Git: diff this" })
			K('n', '<Space>gu', gs.undo_stage_hunk, { desc = "Git: undo stage hunk" })
			K('n', '<Space>gS', gs.stage_buffer, { desc = "Git: stage buffer" })
			K('n', '<Space>gb', gs.blame_line, { desc = "Git: blame line" })
			K('n', '<Space>gv', gs.preview_hunk_inline, { desc = "Git: preview hunk" })
			K('n', '<Space>gU', "<cmd>Gitsigns reset_hunk<cr>", { desc = "Git: reset hunk" })
			K('n', '<Space>gs', "<cmd>Gitsigns stage_hunk<cr>", { desc = "Git: stage hunk" })
			K('n', '<Space>gm', "<cmd>Telescope git_status<cr>", { desc = "Git: find modifications" })

			-- hunks {{{
			K('n', ']c', function()
				if vim.wo.diff then return ']c' end
				vim.schedule(function() gs.next_hunk() end)
				return '<Ignore>'
			end, { expr = true, desc = 'Git: next hunk' })

			K('n', '[c', function()
				if vim.wo.diff then return '[c' end
				vim.schedule(function() gs.prev_hunk() end)
				return '<Ignore>'
			end, { expr = true, desc = 'Git: prev hunk' })
			--,}}}
		end,
	},
	require "lazier" {
		"kdheepak/lazygit.nvim",
		cmd = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile", "LazyGitFilter", "LazyGitFilterCurrentFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			-- -- [LazyGit](<https://github.com/kdheepak/lazygit.nvim>)
			K('n', "<space>gl", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_floating_window_winblend = 0 -- transparency of floating window
			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_floating_window_scaling_factor = 0.9 -- scaling factor for floating window
			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_floating_window_border_chars = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' } -- customize lazygit popup window border characters
			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_floating_window_use_plenary = 0 -- use plenary.nvim to manage floating window if available
			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_use_neovim_remote = 1 -- fallback to 0 if neovim-remote is not installed

			---@diagnostic disable-next-line: inject-field
			vim.g.lazygit_use_custom_config_file_path = 0 -- config file path is evaluated if this value is 1
		end,
	},
}
