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
})

vim.keymap.set('n', '<Space>gg', "<cmd>!git add -A && git commit -m '_' && git push<cr><cr>",
	{ desc = "Git: just push", silent = true })
vim.keymap.set('n', '<Space>gp', "<cmd>!git pull<cr><cr>", { desc = "Git: pull", silent = true })
vim.keymap.set('n', '<Space>gr', "<cmd>!git reset --hard<cr><cr>", { desc = "Git: reset --hard", silent = true })
-- this assumes we correctly did `vim.fn.chdir(vim.env.PWD)` in an autocmd earlier. Otherwise this will often try to execute commands one level in the filetree above.
vim.keymap.set('n', '<Space>gd', gs.diffthis, { desc = "Git: diff this" })
vim.keymap.set('n', '<Space>gu', gs.undo_stage_hunk, { desc = "Git: undo stage hunk" })
vim.keymap.set('n', '<Space>gS', gs.stage_buffer, { desc = "Git: stage buffer" })
vim.keymap.set('n', '<Space>gb', gs.blame_line, { desc = "Git: blame line" })
vim.keymap.set('n', '<Space>gv', gs.preview_hunk_inline, { desc = "Git: preview hunk" })
vim.keymap.set('n', '<Space>gU', "<cmd>Gitsigns reset_hunk<cr>", { desc = "Git: reset hunk" })
vim.keymap.set('n', '<Space>gs', "<cmd>Gitsigns stage_hunk<cr>", { desc = "Git: stage hunk" })
vim.keymap.set('n', '<Space>gf', "<cmd>Telescope git_status<cr>", { desc = "Git: find modifications" })



-- -- [LazyGit](<https://github.com/kdheepak/lazygit.nvim>)
vim.keymap.set('n', "<space>gl", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

vim.g.lazygit_floating_window_winblend = 0 -- transparency of floating window
vim.g.lazygit_floating_window_scaling_factor = 0.9 -- scaling factor for floating window
vim.g.lazygit_floating_window_border_chars = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' } -- customize lazygit popup window border characters
vim.g.lazygit_floating_window_use_plenary = 0 -- use plenary.nvim to manage floating window if available
vim.g.lazygit_use_neovim_remote = 1 -- fallback to 0 if neovim-remote is not installed

vim.g.lazygit_use_custom_config_file_path = 0 -- config file path is evaluated if this value is 1
vim.g.lazygit_config_file_path = '' -- custom config file path
-- OR
vim.g.lazygit_config_file_path = {} -- table of custom config file paths
--
