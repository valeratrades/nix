require("aerial").setup({
	on_attach = function(bufnr)
		vim.keymap.set("n", "<Space>[", "<cmd>AerialPrev<CR>", { buffer = bufnr })
		vim.keymap.set("n", "<Space>]", "<cmd>AerialNext<CR>", { buffer = bufnr })
	end,
})
vim.keymap.set("n", "<Space>a", "<cmd>AerialToggle!<CR>")
