function SetThemeDark()
	vim.cmd.colorscheme("default")
	vim.cmd.colorscheme("github_dark")

	vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })
	local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
	vim.api.nvim_set_hl(0, "NormalNC", { bg = normal.bg })
	vim.api.nvim_set_hl(0, "NormalFloat", { bg = normal.bg })
	vim.api.nvim_set_hl(0, "WinSeparator", { bg = "none" })
	vim.api.nvim_set_hl(0, "CustomGroup", { bg = normal.bg })

	-- To make transparent:
	--vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
	--vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
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
