return require("lazier")({
	"3rd/image.nvim",
	build = false, -- no luarocks needed with magick_cli
	ft = { "markdown" },
	opts = {
		processor = "magick_cli", -- avoids luarocks dependency
		backend = "ueberzug", -- works with alacritty
		integrations = {
			markdown = { enabled = true },
			neorg = { enabled = false },
			typst = { enabled = false },
			html = { enabled = false },
			css = { enabled = false },
		},
		max_width = nil,
		max_height = nil,
		max_width_window_percentage = nil,
		max_height_window_percentage = 50,
		editor_only_render_when_focused = true,
		window_overlap_clear_enabled = true,
		window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
	},
})
