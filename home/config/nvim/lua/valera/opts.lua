-- note that ver{M}; M doesn't affect nothing. As well as blinking values. I can only turn things on and off here. The rest is controlled by alacritty.
local o = vim.opt

o.guicursor =
"n:blinkwait3000-blinkoff50-blinkon400-Cursor/lCursor,i:ver40-blinkwait3000-blinkoff300-blinkon150-Cursor/lCursor,c:ver40-blinkwait3000-blinkoff300-blinkon150-Cursor/lCursor"

-- -- recognise `{{{,}}}` fold markers, but don't fold automatically
o.foldmethod = "marker"
o.foldenable = false
o.foldlevel = 99
--

o.nu = true
--o.relativenumber = true
o.relativenumber = false --TEST: maybe it's easier to just `:$line` instead

o.tabstop = 2
o.softtabstop = 0
o.shiftwidth = 2
o.expandtab = false
o.smartindent = true

o.wrap = true
o.splitright = true

o.showtabline = 2 -- tabline shown even if only 1 file is open // reason: consistency

o.swapfile = false
o.backup = false
o.undofile = true
o.undodir = os.getenv("HOME") .. "/.vim/undodir"
if not vim.fn.isdirectory(vim.fn.expand(vim.o.undodir)) then
	vim.fn.mkdir(vim.fn.expand(o.undodir), "p", "0770") -- ensure created
end

o.hlsearch = false
o.incsearch = true

vim.o.timeoutlen = 700
vim.o.ttimeoutlen = 2

o.scrolloff = 5
o.signcolumn = "yes"
o.isfname:append("@-@")

o.updatetime = 50

--o.colorcolumn = "120" // don't like that it a) wraps around when width is less than what it's set to, b) splits to multiple visual lines when they are longer than what it's set to.

o.title = true
o.titlestring = "nvim: %F"

-- typst.vim
vim.g.typst_output_to_tmp = true

vim.g.autoformat = true
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp" }
o.showmode = false
o.winminwidth = 5

o.modifiable = true

o.showmatch = true
o.joinspaces = false

-- Spelling
--o.spellang = "en_us,fr" // doesn't work
o.spelloptions = "camel"
--o.spellcapcheck =
--[[[.?!]\_[\])'"\t ]\+]] -- default. Can't figure out how to prevent it from forcing capitalization at new line start.
o.spellcapcheck =
""                        -- triggers on line start are too annoying, negating any usefulness of checking caps in other places.
--o.spellfile = os.getenv("HOME") .. "/.config/nvim/spell/en.utf-8.add"
o.spellfile = os.getenv("NIXOS_CONFIG") .. "/home/config/nvim/spell/en.utf-8.add"

-- o.path = "**"

-- -- LaTeX
vim.g.tex_flavor = 'latex'
vim.g.vimtex_view_method = 'zathura'
vim.g.vimtex_quickfix_mode = 0
vim.o.conceallevel = 1
vim.g.tex_conceal = 'abdmg'
vim.g.vimtex_compiler_latexmk = { options = { 'notes.tex', '-shell-escape', '-interaction=nonstopmode' } }
vim.g.vimtex_complete_enabled = 1
vim.g.vimtex_complete_close_braces = 1
vim.g.vimtex_complete_ignore_case = 1
vim.g.vimtex_complete_smart_case = 1
--
