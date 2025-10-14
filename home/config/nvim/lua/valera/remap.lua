local utils = require('valera.utils')
--TODO: switch all `K`s to whichkey
-- Notes for all mappings:
-- 1) never use ':lua', instead use '<cmd>lua', for ':lua' forces us to normal mode.

vim.g.mapleader = " "
K({ "n", "v" }, "-", "<cmd>Oil<cr>")

-- only want copilot enable if it was temporarely suspended by writing a comment.
K("i", "<Esc>", "<Esc><Esc><cmd>lua CommentCopilotEsc()<cr>",
	{ desc = "Allow quick exit from cmp suggestions by doubling <Esc>" })

K("", "<C-e>", "<nop>") -- used as prefix in my tmux
K("", "j", "<nop>")
K("", "k", "<nop>")
K("", "l", "<nop>")
K("", "h", "<nop>")
--K("", "s", multiplySidewaysMovements('h'), { silent = true })
K("", "s", "h", { silent = true })
K("", "r", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
K("", "n", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
--K("", "t", multiplySidewaysMovements('l'), { silent = true })
K("", "t", "l", { silent = true })
K("n", "h", "r")
K("n", "H", "<nop>")
K("n", "H", "R")
K("n", "gf", "gF")
K("", "<MiddleMouse>", "<nop>")

-- Useful Enter key
--K("", "<CR>", "o<Esc>")
K("", "<C-CR>", "O<Esc>")
K("i", "<C-CR>", "<Esc>O")

-- Jumps
--K("", "R", "<C-d>zz")
--K("", "N", "<C-u>zz")
K("", "<C-d>", "<C-d>zz")
K("", "<C-u>", "<C-u>zz")

-- Move line
K("v", "<A-j>", ":m '>+1<cr>gv=gv")
K("v", "<A-k>", ":m '<-2<cr>gv=gv")
K("n", "<A-j>", "V:m '>+1<cr>gv=gv")
K("n", "<A-k>", "V:m '>-2<cr>gv=gv")
K("i", "<A-j>", "<Esc>V:m '>+1<cr>gv=gv")
K("i", "<A-k>", "<Esc>V:m '>-2<cr>gv=gv")

-- -- Consequences
K("n", "j", "nzzzv")
K("n", "k", "Nzzzv")
K("n", "N", "*Ncgn", { noremap = true, silent = true }) -- weird sub of `s` which is not even `s` with semimak.

K("", "L", "<nop>")
K("", "l", "t")
K("", "L", "T")
--
--,}}}

-- Windows {{{
K('n', '<C-w>s', '<C-W>h')
K('n', '<C-w>r', '<C-W>j')
K('n', '<C-w>n', '<C-W>k')
K('n', '<C-w>t', '<C-W>l')

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
K("n", "<C-w><C-h>", "<C-w><C-s><C-w>w", { desc = "windows: new horizontal" }) --

K("n", "<C-w>k", "<cmd>tab sb<cr>", { desc = "C-w>t that is consistent with <C-w>v and <C-w>h" })
K("n", "<C-w>K", function() MoveToNewTab() end, { desc = "windows: move to new tab" })
--,}}}

function MoveToNewTab()
	local current_win = vim.api.nvim_get_current_win()
	vim.cmd("tab sb")
	vim.api.nvim_win_close(current_win, false)
end

-- execute any `g` command in a new vsplit
vim.keymap.set('n', 'gw', function()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w><C-v>', true, false, true), 'n', false)
	vim.api.nvim_feedkeys('g', 'm', false)
end, { noremap = true, silent = true })

-- <C-w>= for normalizing
--

vim.keymap.set('n', '<Space>p', '"+p', { desc = "paste from system clipboard" })


-- Toggle Options
-- local leader doesn't work, so doing manually. Otherwise it'd be "<space> u"
--K("n", "<space>uf", function() Util.format.toggle() end, { desc = "toggle: auto format (global)" })
--K("n", "<space>us", function() Util.toggle("spell") end, { desc = "toggle: Spelling" })
--

-- Tabs
K("n", "gt", "<nop>")
K("n", "gT", "<nop>")
K({ "i", "" }, "<A-l>", "<Esc>gT")
K({ "i", "" }, "<A-h>", "<Esc>gt")
K({ "i", "" }, "<A-v>", "<Esc>g<Tab>")
K({ "i", "" }, "<A-0>", "<Esc><cmd>tablast<cr>")
K({ "i", "" }, "<A-9>", "<Esc><cmd>tablast<cr>") -- don't like it on 9, but want to keep compatibility with chrome
for i = 1, 8 do
	K("", '<A-' .. i .. '>', '<Esc><cmd>tabn ' .. i .. '<cr>', { noremap = true, silent = true })
end
for i = 1, 8 do
	K("i", '<A-' .. i .. '>', '<Esc><cmd>tabn ' .. i .. '<cr>', { noremap = true, silent = true })
end
K("", "<A-o>", "<nop>")
K("", "<A-O>", "<nop>")
K({ "i", "" }, "<A-u>", "<Esc><cmd>tabmove -<cr>")
K({ "i", "" }, "<A-y>", "<Esc><cmd>tabmove +<cr>")
K({ "i", "" }, "<A-U>", "<Esc><cmd>tabmove 0<cr>")
K({ "i", "" }, "<A-Y>", "<Esc><cmd>tabmove $<cr>")
--

-- -- Standards and the Consequences
K("", "<C-'>", "\"+ygv\"_d")
K("", "<C-b>", "\"+y")

K("i", "<C-del>", "X<Esc>ce") -- n mappings for <del> below rely on this
K("v", "<bs>", "d")
K("n", "<bs>", "i<bs>")
K("n", "<del>", "i<del>")
K("n", "<C-del>", "a<C-del>", { remap = true })

K("n", "<C-A>", "ggVG")
-- Consequences
K('', '<C-z>', '<C-a>')
--
-- --

local function getPopups()
	return vim.fn.filter(vim.api.nvim_tabpage_list_wins(0),
		function(_, e) return vim.api.nvim_win_get_config(e).zindex end)
end
local function killPopups()
	vim.fn.map(getPopups(), function(_, e)
		vim.api.nvim_win_close(e, false)
	end)
end

K("n", "<Esc>", function()
	vim.cmd.noh()
	killPopups()
	--vim.cmd("PeekClose")
	print(" ")
end)

K('n', '<C-z>', '<Nop>')
K('n', "<Space><C-z>", "<C-z>")

local function saveSessionIfOpen(cmd, hook_before)
	hook_before = hook_before or ""
	return function()
		if vim.g.persisting then
			vim.cmd("SessionSave")
		end
		local mode = vim.api.nvim_get_mode().mode
		if mode == 'i' then
			Ft("<Esc>l")
		end
		vim.cmd.noh()
		killPopups()
		if hook_before ~= "" then
			vim.cmd("wa!")
		end
		vim.cmd(cmd)
	end
end

K({ "", "i" }, "<A-c>", "<cmd>q!<cr>")
K({ "", "i" }, "<A-C>", "<cmd>tabdo bd<cr>")
K({ "", "i" }, "<A-a>", saveSessionIfOpen('qa!', 'wa!'), { desc = "save everything and exit" })
K({ "", "i" }, "<A-;>", '<cmd>qa!<cr>')
K({ "", "i" }, "<A-w>", saveSessionIfOpen('w!'))

K("", ";", ":")
K("", ":", ";")

K("n", "J", "mzJ`z")

K("n", "<space>y", "\"+y")
K("v", "<space>y", "\"+y")
K("n", "<space>Y", "\"+Y")
K("x", "<space>p", "\"_dP")

K({ "n", "v" }, "<space>d", "\"_d")
K("n", "x", "\"_x")
K("n", "X", "\"_X")
K("", "c", "\"_c")
K("", "C", "\"_C")

--K("n", "<C-F>", "<cmd>silent !tmux neww tmux-sessionizer<cr>")

K("n", "<space><space>n", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>")

-- select the pasted
K("n", "gp", function()
	return "`[" .. vim.fn.strpart(vim.fn.getregtype(), 0, 1) .. "`]"
end, { expr = true })

K("n", "H", "H^")
K("n", "M", "M^")
K("n", "L", "L^")

-- Tries to correct spelling of the word under the cursor
K("n", "z1", "mx1z=`x", { silent = true })
K("n", "z2", "u2z=`x", { silent = true })
K("n", "z3", "u3z=`x", { silent = true })
K("n", "z4", "u4z=`x", { silent = true })
K("n", "z5", "u5z=`x", { silent = true })
K("n", "z6", "u6z=`x", { silent = true })
K("n", "z7", "u7z=`x", { silent = true })
K("n", "z8", "u8z=`x", { silent = true })
K("n", "z9", "u9z=`x", { silent = true })

K('n', '<space>clr', 'vi""8di\\033[31m<Esc>"8pa\\033[0m<Esc>', { desc = "add red escapecode" })
K('n', '<space>clg', 'vi""8di\\033[32m<Esc>"8pa\\033[0m<Esc>', { desc = "add green escapecode" })
K('n', '<space>cly', 'vi""8di\\033[33m<Esc>"8pa\\033[0m<Esc>', { desc = "add yellow escapecode" })
K('n', '<space>clb', 'vi""8di\\033[34m<Esc>"8pa\\033[0m<Esc>', { desc = "add blue escapecode" })

K('', '<space>.', '<cmd>tabe .<cr>')

-- zero width space digraph
vim.cmd.digraph("zs " .. 0x200b)

K('n', 'U', '<C-r>', { noremap = true, desc = "helix: redo" })
K('', '<C-r>', '<nop>') -- later changed to `lsp refresh` in lsp.lua
K('n', '<tab>', 'i<tab>')

-- trying out:
K("i", "<c-r><c-r>", "<c-r>\"");
K("n", "<space>`", "~hi");
K("v", "<space>`", "~gvI");

-- gf and if it doesn't exist, create it
local function forceGoFile()
	local fname = vim.fn.expand("<cfile>")
	local path = vim.fn.expand("%:p:h") .. "/" .. fname
	if vim.fn.filereadable(path) ~= 1 then
		vim.cmd("silent! !touch " .. path)
	end
	vim.cmd.norm("gf")
end
K("n", "<Space>gf", forceGoFile);


K("", "<M-o>", "<C-o>zt", { desc = "Because <C-i> doesn't work with tmux" })
K("", "<M-i>", "<C-i>zt", { desc = "Because <C-i> doesn't work with tmux" })
K("", "<C-o>", "<C-o>zz")
K("", "<C-i>", "<C-i>zz")

-- -- Built-in Terminal (complete shit btw, hardly a reason to use it)
K("t", "<Esc><Esc>", "<C-\\><C-n>")
--K("t", "<Esc>", "<C-\\><C-n>")
K("t", "<C-w>s", "<C-\\><C-N><C-w>h")
K("t", "<C-w>r", "<C-\\><C-N><C-w>j")
K("t", "<C-w>n", "<C-\\><C-N><C-w>k")
K("t", "<C-w>t", "<C-\\><C-N><C-w>l")
--

local function copyFileLineCol()
	local file = vim.fn.expand('%')
	local line = vim.fn.line('.')
	local col = vim.fn.col('.')
	local location = string.format("%s:%d:%d", file, line, col)
	return location
end

K("", "<Space>ay", function() vim.fn.setreg('"', copyFileLineCol()) end, { desc = "copy file:line:col to \" buffer" })
K("", "<Space>a<Space>y", function() vim.fn.setreg('+', copyFileLineCol()) end,
	{ desc = "copy file:line:col to + buffer" })

local function goto_file_line_column_or_function(file_line_or_func)
	if string.match(file_line_or_func, "([^:]+):(%d+):(%d+)") then -- file:line:col
		local file, line, col = string.match(file_line_or_func, "([^:]+):(%d+):(%d+)")
		vim.cmd('edit ' .. file)
		vim.fn.cursor(tonumber(line), tonumber(col))
		vim.cmd("normal! zz")
	elseif string.match(file_line_or_func, "([^:]+):(%d+)") then -- file:line (without col)
		local file, line = string.match(file_line_or_func, "([^:]+):(%d+)")
		vim.cmd("edit " .. file)
		vim.fn.cursor(tonumber(line), 1)
		vim.cmd("normal! zz")
	elseif string.match(file_line_or_func, "::") then -- file::mod::another_mod::function_name (LSP symbol path)
		local function_name
		for segment in string.gmatch(file_line_or_func, "([^:]+)") do
			function_name = segment
		end

		local builtin = require('telescope.builtin')
		-- Use LSP to find the function location if available
		local lsp_active = #vim.lsp.get_clients() > 0
		if lsp_active then
			local actions = require('telescope.actions')
			builtin.lsp_workspace_symbols({
				query = function_name,
				symbols = { "function", "method" },
				on_complete = {
					--FUCK: puts me in insert
					function(picker)
						--actions.file_edit(picker.prompt_bufnr)
						actions.select_default(picker.prompt_bufnr)
						vim.cmd("normal! zt")
						--HACK
						vim.defer_fn(function()
							vim.cmd("stopinsert")
						end, 30)
					end,
				},
			})
		else
			print("No LSP clients found. Falling back to live_grep")
			builtin.live_grep({ default_text = function_name .. [[\(]], hidden = true, no_ignore = true, file_ignore_patterns = { ".git/", "target/", "%.lock" } })
		end
	else -- file only
		local file = file_line_or_func
		local expanded_file = vim.fn.expand(file)
		if vim.fn.filereadable(expanded_file) == 1 then
			vim.cmd("edit " .. expanded_file)
		else
			print("Invalid format. Expected: file:line:col or file:function_name")
		end
	end
end


vim.api.nvim_create_user_command("Gf", function(opts)
	local arg = opts.fargs[1]
	-- If no argument is passed, get the system clipboard contents
	if not arg then
		arg = vim.fn.getreg("+")
	end
	goto_file_line_column_or_function(arg)
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
