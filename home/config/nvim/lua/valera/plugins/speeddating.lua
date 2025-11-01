return {
	"tpope/vim-speeddating",
	init = function()
		vim.g.speeddating_no_mappings = 1
		K({ "n", "v" }, "<C-z>", "<cmd>call speeddating#increment(v:count1)<cr>")
		K({ "n", "v" }, "<C-x>", "<cmd>call speeddating#increment(-v:count1)<cr>")
		K("n", "d<C-z>", "<cmd>call speeddating#timestamp(0,v:count)<cr>")
		K("n", "d<C-x>", "<cmd>call speeddating#timestamp(1,v:count)<cr>")
	end,
}
