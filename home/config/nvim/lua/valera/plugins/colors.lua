return require "lazier" {
	"projekt0n/github-nvim-theme",
	config = function()
		function SetThemeDark()
			vim.cmd.colorscheme("default")
			vim.cmd.colorscheme("github_dark")

			for _, g in ipairs { "Normal", "NormalNC", "NormalFloat", "FloatBorder", "SignColumn", "WinSeparator" } do
				local hl = vim.api.nvim_get_hl(0, { name = g })
				hl.bg = nil
				vim.api.nvim_set_hl(0, g, hl)
			end
		end

		function SetThemeLight()
			vim.cmd.colorscheme("github_light_high_contrast")
			--vim.cmd.colorscheme("github_light")

		end

		function SetThemeSystem()
			local handle = io.popen("gsettings get org.gnome.desktop.interface color-scheme")
			if handle == nil then
				return
			end
			local result = handle:read("*a")
			handle:close()

			if string.match(string.lower(result), "dark") then
				SetThemeDark()
			else
				SetThemeLight()
			end
		end

		SetThemeSystem()

		-- -- expand shared regex syntax hightlighting
		--TODO: add NB, Q, PERF etc
		--
	end
}
