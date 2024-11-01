require("ibl").setup{
	indent = {
		char = "┊",
    highlight = "Comment",
		smart_indent_cap = true
	},
}

require("ibl").overwrite {
	exclude = { filetypes = {"help", "dashboard", "lazy", "NvimTree", "json"} }
}



local hooks = require("ibl.hooks")
hooks.register(
	-- no clue what the next line does, but without it everything breaks.
	hooks.type.WHITESPACE,
	hooks.builtin.hide_first_tab_indent_level
)
