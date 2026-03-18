--TODO: render-markdown is only here because we need it for inline images. If we find a way to get
-- inline images without it, remove this plugin entirely.
return require("lazier")({
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"echasnovski/mini.icons",
	},
	opts = {
		enabled = false,
		render_modes = { "n", "c" },
		latex = { enabled = false },
	},
	config = function(_, opts)
		require("render-markdown").setup(opts)
		require("render-markdown").disable()

		vim.api.nvim_create_user_command("MarkdownInline", function()
			require("render-markdown").enable()
			require("lazy").load({ plugins = { "image.nvim" } })
			require("image").enable()
			vim.cmd("doautocmd BufWinEnter")
		end, { desc = "Render markdown inline (with images)" })

		vim.api.nvim_create_user_command("MarkdownNormal", function()
			require("render-markdown").disable()
			require("image").disable()
		end, { desc = "Return to normal markdown editing" })
	end,
})
