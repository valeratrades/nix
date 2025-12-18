return require("lazier")({
	"HakonHarnes/img-clip.nvim",
	event = "VeryLazy",
	opts = {
		default = {
			dir_path = "assets",
		},
		filetypes = {
			markdown = {
				url_encode_path = true,
				template = "![$CURSOR]($FILE_PATH)",
			},
			typst = {
				template = '#image("$FILE_PATH")',
			},
		},
	},
	keys = {
		{
			"<C-v>",
			function()
				local ft = vim.bo.filetype
				if ft == "markdown" or ft == "typst" then
					require("img-clip").paste_image()
				else
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-v>", true, false, true), "n", false)
				end
			end,
			desc = "Paste image from clipboard",
		},
	},
})
