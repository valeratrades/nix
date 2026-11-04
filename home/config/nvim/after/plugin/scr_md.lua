-- gates after/queries/markdown/injections.scm to scripters' `*.scr.md`
vim.treesitter.query.add_predicate("scr-md?", function(_, _, source)
	return type(source) == "number" and vim.api.nvim_buf_get_name(source):match("%.scr%.md$") ~= nil
end, { force = true })
