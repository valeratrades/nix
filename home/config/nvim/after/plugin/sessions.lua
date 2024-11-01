-- "<space>sp" to search for session with Telescope
require("persisted").setup({
	save_dir = vim.fn.expand(vim.fn.stdpath("data") .. "/sessions/"),
	silent = true,
	autosave = false,
	autoload = false,
	follow_cwd = true,
	allowed_dirs = nil,
	ignored_dirs = { "tmp", "s", ".config" },
	telescope = {
		reset_prompt_after_deletion = true,
	},
})

vim.keymap.set('n', '<space>sel', "<cmd>SessionLoad<cr><cmd>SessionSave<cr>", { desc = "Session: Load" })
vim.keymap.set('n', '<space>ses', "<cmd>SessionSave<cr><cmd>lua print('session saved')<cr>", { desc = "Session: Save" })
vim.keymap.set('n', '<space>sei', "<cmd>SessionStart<cr><cmd>lua print('session started')<cr>",
	{ desc = "Session: Init" })
vim.keymap.set('n', '<space>seq', "<cmd>SessionStop<cr><cmd>lua print('stopped recording session')<cr>",
	{ desc = "Session: Quit" })
