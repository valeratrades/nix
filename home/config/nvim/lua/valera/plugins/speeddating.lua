return {
	"tpope/vim-speeddating",
	init = function()
		vim.g.speeddating_no_mappings = 1
		K({ "n", "v" }, "<C-z>", "<cmd>call speeddating#increment(v:count1)<cr>", { desc = "Increment date/time" })
		K({ "n", "v" }, "<C-x>", "<cmd>call speeddating#increment(-v:count1)<cr>", { desc = "Decrement date/time", overwrite = true })
		K("n", "d<C-z>", "<cmd>call speeddating#timestamp(0,v:count)<cr>", { desc = "Insert UTC timestamp" })
		K("n", "d<C-x>", "<cmd>call speeddating#timestamp(1,v:count)<cr>", { desc = "Insert local timestamp" })
	end,
}
