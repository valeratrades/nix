vim.g.mapleader = " "
K({ "n", "v" }, "-", "<cmd>Oil<cr>", { desc = "Open Oil" })

-- only want copilot enable if it was temporarely suspended by writing a comment.
--K("i", "<Esc>", "<Esc><Esc><cmd>lua CommentCopilotEsc()<cr>",
--	{ desc = "Exit cmp suggestions", overwrite = true })

K("", "<C-e>", "<nop>", { desc = "Nop (tmux prefix)", overwrite = true })
--K("", "s", multiplySidewaysMovements('h'), { silent = true })
K("", "s", "h", { desc = "Left", silent = true, overwrite = true })
K("", "r", "v:count == 0 ? 'gj' : 'j'", { desc = "Down (display line)", expr = true, silent = true, overwrite = true })
K("", "n", "v:count == 0 ? 'gk' : 'k'", { desc = "Up (display line)", expr = true, silent = true, overwrite = true })
--K("", "t", multiplySidewaysMovements('l'), { silent = true })
K("", "t", "l", { desc = "Right", silent = true, overwrite = true })
K("n", "h", "r", { desc = "Replace char", overwrite = true })
K("n", "H", "R", { desc = "Replace mode", overwrite = true })
K("n", "gf", "gF", { desc = "Go to file (with line)", overwrite = true })
K("", "<MiddleMouse>", "<nop>", { desc = "Nop" })

K("i", "<C-CR>", "<Esc>O", { desc = "Insert line above" })

-- Jumps
--K("", "R", "<C-d>zz")
--K("", "N", "<C-u>zz")
K("", "<C-d>", "<C-d>zz", { desc = "Page down (centered)", overwrite = true })
K("", "<C-u>", "<C-u>zz", { desc = "Page up (centered)", overwrite = true })

-- Move line
K("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move line down" })
K("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move line up" })
K("n", "<A-j>", "V:m '>+1<cr>gv=gv", { desc = "Move line down" })
K("n", "<A-k>", "V:m '>-2<cr>gv=gv", { desc = "Move line up" })
K("i", "<A-j>", "<Esc>V:m '>+1<cr>gv=gv", { desc = "Move line down" })
K("i", "<A-k>", "<Esc>V:m '>-2<cr>gv=gv", { desc = "Move line up" })

-- -- Consequences
K("n", "j", "nzzzv", { desc = "Next search (centered)", overwrite = true })
K("n", "k", "Nzzzv", { desc = "Prev search (centered)", overwrite = true })
K("n", "N", "*Ncgn", { desc = "Change next word", silent = true, overwrite = true })

K("", "l", "t", { desc = "Till char", overwrite = true })
--
--,}}}

-- Windows {{{
K('n', '<C-w>s', '<C-w>h', { desc = 'Win left' })
K('n', '<C-w>r', '<C-w>j', { desc = 'Win down' })
K('n', '<C-w>n', '<C-w>k', { desc = 'Win up' })
K('n', '<C-w>t', '<C-w>l', { desc = 'Win right' })

K('n', '<C-w>S', '<cmd>wincmd H<cr>', { desc = 'move window left' })
K('n', '<C-w>R', '<cmd>wincmd J<cr>', { desc = 'move window down' })
K('n', '<C-w>N', '<cmd>wincmd K<cr>', { desc = 'move window up' })
K('n', '<C-w>T', '<cmd>wincmd L<cr>', { desc = 'move window right' })

K("n", "<C-Right>", "<cmd>vertical resize -2<cr>", { desc = "windows: decrease width" })
K("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "windows: decrease height" })
K("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "windows: increase height" })
K("n", "<C-Left>", "<cmd>vertical resize +2<cr>", { desc = "windows: increase width" })

K("n", "<C-w>o", "<C-w><C-s><C-w>w", { desc = "windows: new horizontal" })
K("n", "<C-w>O", "<C-w><C-v>", { desc = "windows: new vertical" })

K("n", "<C-w>k", "<cmd>tab sb<cr>", { desc = "C-w>t that is consistent with <C-w>v and <C-w>h" })
K("n", "<C-w>K", function() MoveToNewTab() end, { desc = "windows: move to new tab" })

--Q: is this the correct place for it?
K('n', '<C-w>v', '<C-w>w', { desc = 'windows: literally <C-w>w' })
K('n', '<C-w>V', '<cmd>tabprevious<cr>', { desc = 'windows: move to previously active tab' })
K('n', "<C-w><C-v>", "<nop>", { desc = 'Nop' })

K('n', '<C-w>x', '<cmd>tabclose<cr>', { desc = 'windows: tabclose' })
--,}}}

function MoveToNewTab()
	local current_win = vim.api.nvim_get_current_win()
	vim.cmd("tab sb")
	vim.api.nvim_win_close(current_win, false)
end

-- execute any `g` command in a new vsplit
K('n', 'gw', function()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w><C-v>', true, false, true), 'n', false)
	vim.api.nvim_feedkeys('g', 'm', false)
end, { desc = 'Execute g command in vsplit', silent = true, overwrite = true })

-- <C-w>= for normalizing
--

K('n', '<Space>p', '"+p', { desc = "paste from system clipboard" })


-- Toggle Options
-- local leader doesn't work, so doing manually. Otherwise it'd be "<space> u"
--K("n", "<space>uf", function() Util.format.toggle() end, { desc = "toggle: auto format (global)" })
--K("n", "<space>us", function() Util.toggle("spell") end, { desc = "toggle: Spelling" })
--

-- Tabs
K("n", "gt", "<nop>", { desc = "Nop (use Alt-h)", overwrite = true })
K("n", "gT", "<nop>", { desc = "Nop (use Alt-l)", overwrite = true })
K({ "i", "" }, "<A-l>", "<Esc>gT", { desc = "Tab prev" })
K({ "i", "" }, "<A-h>", "<Esc>gt", { desc = "Tab next" })
K({ "i", "" }, "<A-v>", "<Esc>g<Tab>", { desc = "Tab last visited" })
K({ "i", "" }, "<A-0>", "<Esc><cmd>tablast<cr>", { desc = "Tab last" })
K({ "i", "" }, "<A-9>", "<Esc><cmd>tablast<cr>", { desc = "Tab last" })
for i = 1, 8 do
	K("", '<A-' .. i .. '>', '<Esc><cmd>tabn ' .. i .. '<cr>', { desc = 'Tab ' .. i, silent = true })
end
for i = 1, 8 do
	K("i", '<A-' .. i .. '>', '<Esc><cmd>tabn ' .. i .. '<cr>', { desc = 'Tab ' .. i, silent = true })
end
K("", "<A-o>", "<nop>", { desc = "Nop" })
K("", "<A-O>", "<nop>", { desc = "Nop" })
K({ "i", "" }, "<A-u>", "<Esc><cmd>tabmove -<cr>", { desc = "Tab move left" })
K({ "i", "" }, "<A-y>", "<Esc><cmd>tabmove +<cr>", { desc = "Tab move right" })
K({ "i", "" }, "<A-U>", "<Esc><cmd>tabmove 0<cr>", { desc = "Tab move first" })
K({ "i", "" }, "<A-Y>", "<Esc><cmd>tabmove $<cr>", { desc = "Tab move last" })
--

-- -- Standards and the Consequences
K("", "<C-'>", "\"+ygv\"_d", { desc = "Cut to clipboard" })
K("", "<C-b>", "\"+y", { desc = "Copy to clipboard", overwrite = true })

K("i", "<C-del>", "X<Esc>ce", { desc = "Delete word forward" })
K("v", "<bs>", "d", { desc = "Delete selection" })
K("n", "<bs>", "i<bs>", { desc = "Backspace" })
K("n", "<del>", "i<del>", { desc = "Delete" })
K("n", "<C-del>", "a<C-del>", { desc = "Delete word forward", remap = true })

function SelectAll()
	-- `ggVG`, but nothing is added to jumplist, and cursor position is restored on exit from visual mode
	local bufnr = 0
	local end_line = vim.api.nvim_buf_line_count(bufnr)
	local curpos = vim.api.nvim_win_get_cursor(0)
	local view = vim.fn.winsaveview() -- persist cursor position relative to view

	vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
	vim.fn.setpos("'>", { bufnr, end_line, 1000000, 0 })

	vim.cmd("normal! gv")

	vim.api.nvim_create_autocmd("ModeChanged", {
		pattern = { "v:n", "V:n", ":n" }, -- all visual → normal exits
		once = true,
		callback = function()
			vim.api.nvim_win_set_cursor(0, curpos)
			vim.fn.winrestview(view)
		end,
	})
end

K("n", "<C-a>", SelectAll, { desc = "select all", overwrite = true })
-- --

K("n", "<Esc>", function()
	vim.cmd.noh()
	require('rust_plugins').kill_popups()
	--vim.cmd("PeekClose")
	print(" ")
end, { desc = "Clear search and popups" })

K('n', '<C-z>', '<Nop>', { desc = "Nop (use Space+C-z)" })
K('n', "<Space><C-z>", "<C-z>", { desc = "Suspend" })

K({ "", "i" }, "<A-c>", "<cmd>q!<cr>", { desc = "Quit window" })
K({ "", "i" }, "<A-C>", "<cmd>tabdo bd<cr>", { desc = "Close all buffers" })
K({ "", "i" }, "<A-a>", function()
	require('rust_plugins').save_session_if_open('qa!', 'wa!')
end, { desc = "Save and quit all" })
K({ "", "i" }, "<A-;>", '<cmd>qa!<cr>', { desc = "Quit all" })
K({ "", "i" }, "<A-w>", function()
	require('rust_plugins').save_session_if_open('w!', nil)
end, { desc = "Save" })

K("", ";", ":", { desc = "Command mode", overwrite = true })
K("", ":", ";", { desc = "Repeat f/t", overwrite = true })

K("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)", overwrite = true })

K("n", "<space>y", "\"+y", { desc = "Yank to clipboard" })
K("v", "<space>y", "\"+y", { desc = "Yank to clipboard" })
K("n", "<space>Y", "\"+Y", { desc = "Yank line to clipboard" })
K("x", "<space>p", "\"_dP", { desc = "Paste (preserve register)" })

K({ "n", "v" }, "<space>d", "\"_d", { desc = "Delete (to void)" })
K("n", "x", "\"_x", { desc = "Delete char (to void)", overwrite = true })
K("n", "X", "\"_X", { desc = "Delete char back (to void)", overwrite = true })
K("", "c", "\"_c", { desc = "Change (to void)", overwrite = true })
K("", "C", "\"_C", { desc = "Change to EOL (to void)", overwrite = true })

K("n", "<space><space>n", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>", { desc = "Substitute word" })

-- select the pasted
K("n", "gp", function()
	return "`[" .. vim.fn.strpart(vim.fn.getregtype(), 0, 1) .. "`]"
end, { desc = "Select pasted text", expr = true, overwrite = true })

K("n", "H", "H^", { desc = "Top of screen (first char)", overwrite = true })
K("n", "M", "M^", { desc = "Middle of screen (first char)", overwrite = true })
K("n", "L", "L^", { desc = "Bottom of screen (first char)", overwrite = true })

-- Tries to correct spelling of the word under the cursor
K("n", "z1", "mx1z=`x", { desc = "Fix spelling (1st suggestion)", silent = true })
K("n", "z2", "u2z=`x", { desc = "Fix spelling (2nd suggestion)", silent = true })
K("n", "z3", "u3z=`x", { desc = "Fix spelling (3rd suggestion)", silent = true })
K("n", "z4", "u4z=`x", { desc = "Fix spelling (4th suggestion)", silent = true })
K("n", "z5", "u5z=`x", { desc = "Fix spelling (5th suggestion)", silent = true })
K("n", "z6", "u6z=`x", { desc = "Fix spelling (6th suggestion)", silent = true })
K("n", "z7", "u7z=`x", { desc = "Fix spelling (7th suggestion)", silent = true })
K("n", "z8", "u8z=`x", { desc = "Fix spelling (8th suggestion)", silent = true })
K("n", "z9", "u9z=`x", { desc = "Fix spelling (9th suggestion)", silent = true })

K('n', '<space>clr', 'vi""8di\\033[31m<Esc>"8pa\\033[0m<Esc>', { desc = "add red escapecode" })
K('n', '<space>clg', 'vi""8di\\033[32m<Esc>"8pa\\033[0m<Esc>', { desc = "add green escapecode" })
K('n', '<space>cly', 'vi""8di\\033[33m<Esc>"8pa\\033[0m<Esc>', { desc = "add yellow escapecode" })
K('n', '<space>clb', 'vi""8di\\033[34m<Esc>"8pa\\033[0m<Esc>', { desc = "add blue escapecode" })

K('', '<space>.', '<cmd>tabe .<cr>', { desc = "Open . in new tab" })

-- zero width space digraph
vim.cmd.digraph("zs " .. 0x200b)

K('n', 'U', '<C-r>', { desc = "helix: redo", overwrite = true }) -- '<C-r>` is then used by lsp for `refresh` action
K('n', '<tab>', 'i<tab>', { desc = "Insert tab", overwrite = true })

-- trying out:
K("i", "<c-r><c-r>", "<c-r>\"", { desc = "Paste unnamed register" });
K("n", "<space>`", "~hi", { desc = "Toggle case, insert" });
K("v", "<space>`", "~gvI", { desc = "Toggle case, insert start" });

-- gf and if it doesn't exist, create it
local function forceGoFile()
	local fname = vim.fn.expand("<cfile>")
	local path = vim.fn.expand("%:p:h") .. "/" .. fname
	if vim.fn.filereadable(path) ~= 1 then
		vim.cmd("silent! !touch " .. path)
	end
	vim.cmd.norm("gf")
end
K("n", "<Space>gf", forceGoFile, { desc = "Go to file (create if missing)" });


K("", "<M-o>", "<C-o>zt", { desc = "Jump back (top)", overwrite = true })
K("", "<M-i>", "<C-i>zt", { desc = "Jump forward (top)" })
K("", "<C-o>", "<C-o>zz", { desc = "Jump back (center)", overwrite = true })
K("", "<C-i>", "<C-i>zz", { desc = "Jump forward (center)", overwrite = true })

-- -- Built-in Terminal (complete shit btw, hardly a reason to use it)
K("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
--K("t", "<Esc>", "<C-\\><C-n>")
K("t", "<C-w>s", "<C-\\><C-N><C-w>h", { desc = "Win left from terminal", overwrite = true })
K("t", "<C-w>r", "<C-\\><C-N><C-w>j", { desc = "Win down from terminal" })
K("t", "<C-w>n", "<C-\\><C-N><C-w>k", { desc = "Win up from terminal" })
K("t", "<C-w>t", "<C-\\><C-N><C-w>l", { desc = "Win right from terminal" })
--

local function copyFileLineCol()
	local file = vim.fn.expand('%:p') -- absolute path
	local mode = vim.fn.mode()

	if mode == 'v' or mode == 'V' or mode == '\22' then -- visual, visual-line, visual-block
		local start_pos = vim.fn.getpos("v")
		local end_pos = vim.fn.getpos(".")
		local start_line, start_col = start_pos[2], start_pos[3]
		local end_line, end_col = end_pos[2], end_pos[3]
		return string.format("%s:{%d:%d; %d:%d}", file, start_line, start_col, end_line, end_col)
	else
		local line = vim.fn.line('.')
		local col = vim.fn.col('.')
		return string.format("%s:%d:%d", file, line, col)
	end
end

local function copyFilePath()
	return vim.fn.expand('%:p') -- absolute path
end

K("", "<Space>ay", function() vim.fn.setreg('"', copyFileLineCol()) end, { desc = "copy file:line:col to \" buffer" })
K("", "<Space>a<Space>y", function() vim.fn.setreg('+', copyFileLineCol()) end,
	{ desc = "copy file:line:col to + buffer" })
K("", "<Space>aY", function() vim.fn.setreg('"', copyFilePath()) end, { desc = "copy filepath to \" buffer" })
K("", "<Space>a<Space>Y", function() vim.fn.setreg('+', copyFilePath()) end, { desc = "copy filepath to + buffer" })

vim.api.nvim_create_user_command("Gf", function(opts)
	local arg = opts.fargs[1]
	-- If no argument is passed, get the system clipboard contents
	if not arg then
		arg = vim.fn.getreg("+")
	end
	require('rust_plugins').goto_file_line_column_or_function(arg)
end, {
	nargs = "*",
	complete = function(_, line)
		-- Provide completion only for files, assuming Neovim's file completion
		local l = vim.split(line, "%s+")
		if #l == 2 then
			-- Perform file completion (using Neovim's built-in)
			return vim.fn.getcompletion(l[2], "file")
		end

		return {}
	end,
})

K("n", "<Space>c", "f}i<Cr><Esc>kA<Cr>", { desc = "multi-line clenched curlies" }) -- bigram chosen for "Space the curlies"

-- Default macro behavior (recursive-macro.nvim overrides q)
K("n", "<Space>q", "q", { desc = "Record macro (default q)", remap = false })

-- Add undo break-points {{{1
K("i", "^M", "^M<c-g>u", { desc = "Enter with undo break" })
K("i", ",", ",<c-g>u", { desc = "Comma with undo break" })
K("i", ".", ".<c-g>u", { desc = "Period with undo break" })
K("i", ";", ";<c-g>u", { desc = "Semicolon with undo break" })
--,}}}1
