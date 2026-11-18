vim.opt_local.spell = true
vim.fn.matchadd("@markup.link", [=[\[[^]]\+\](\S\{-}\.typ\\#[^)]\+)]=], 20) -- cross-file md link (v-utils md.typ); tinymist sees plain text
vim.api.nvim_create_autocmd("BufWritePre", {
	group = vim.api.nvim_create_augroup("typst_align_" .. vim.api.nvim_get_current_buf(), { clear = true }),
	buffer = 0,
	callback = function(args) require("valera.typst_align")(args.buf) end,
})
