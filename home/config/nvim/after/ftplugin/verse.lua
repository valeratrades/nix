vim.bo.commentstring = "#%s"
vim.bo.comments = "s:<#,m: ,e:#>,:#"

-- Verse is offside-scoped, so indent width is load-bearing rather than cosmetic;
-- 4 spaces is what Epic's own sources and the Book of Verse use.
vim.bo.expandtab = true
vim.bo.shiftwidth = 4
vim.bo.tabstop = 4
vim.bo.softtabstop = 4
