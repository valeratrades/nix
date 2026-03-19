return require("lazier")({
	"3rd/image.nvim",
	build = false, -- no luarocks needed with magick_cli
	lazy = true, -- only loaded explicitly (via MarkdownUberzug or telescope)
	opts = {
		processor = "magick_cli", -- avoids luarocks dependency
		backend = (function()
			local term = vim.env.TERM_PROGRAM or ""
			-- also check through tmux, which strips TERM_PROGRAM
			if term == "" and vim.env.TMUX then
				term = vim.fn.system("tmux show-environment TERM_PROGRAM 2>/dev/null"):match("=(.+)") or ""
			end
			local kitty_terms = { kitty = true, ghostty = true, WezTerm = true }
			if vim.env.KITTY_WINDOW_ID or kitty_terms[term] then
				return "kitty"
			end
			return "ueberzug"
		end)(),
		integrations = {
			markdown = {
				enabled = true,
				resolve_image_path = function(document_path, image_url, fallback)
					if image_url:match("%.excalidraw$") then
						local abs = fallback(document_path, image_url)
						if vim.fn.filereadable(abs) == 1 then
							local svg = "/tmp/markdown_svg_compile" .. abs .. ".svg"
							vim.fn.mkdir(vim.fn.fnamemodify(svg, ":h"), "p")
							if vim.fn.filereadable(svg) == 0 or vim.fn.getftime(svg) < vim.fn.getftime(abs) then
								vim.fn.system({ "excalidraw_export", abs, svg })
							end
							return svg
						end
					end
					return fallback(document_path, image_url)
				end,
			},
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
