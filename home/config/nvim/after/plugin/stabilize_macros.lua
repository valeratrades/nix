-- Detect number blocks in a line, treating ISO dates (YYYY-MM-DD) as a single block.
-- Returns list of {s=col (0-indexed)} entries in left-to-right order.
local function get_number_blocks(line)
	local blocks = {}
	local i = 1
	while i <= #line do
		local ds, de = line:find('%d%d%d%d%-%d%d%-%d%d', i)
		local ns, ne = line:find('%d+', i)
		if ds and ds == ns then
			table.insert(blocks, { s = ds - 1 })
			i = de + 1
		elseif ns then
			table.insert(blocks, { s = ns - 1 })
			i = ne + 1
		else
			break
		end
	end
	return blocks
end

-- Replace all number blocks with a fixed placeholder for structural comparison.
local function get_skeleton(line)
	local s = line:gsub('%d%d%d%d%-%d%d%-%d%d', '\0')
	return (s:gsub('%d+', '\0'))
end

-- Increment all number blocks in `lnum` (1-indexed) by `delta`, right to left.
-- Uses speeddating#increment so dates are handled correctly.
local function increment_line_blocks(lnum, delta)
	if delta == 0 then return end
	local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
	local blocks = get_number_blocks(line)
	for i = #blocks, 1, -1 do
		vim.api.nvim_win_set_cursor(0, { lnum, blocks[i].s })
		vim.fn['speeddating#increment'](delta)
	end
end

-- Visual mode: called after <esc> so '< and '> marks are already set.
-- Asserts linewise visual, asserts all lines have same structure,
-- then uses the bottom line as baseline and increments upward.
function OrderRisingVisual()
	if vim.fn.visualmode() ~= 'V' then
		vim.notify("orderRising: requires linewise visual (V) mode", vim.log.levels.ERROR)
		return
	end

	local start_line = vim.fn.line("'<")
	local end_line   = vim.fn.line("'>")

	if start_line == end_line then
		vim.notify("orderRising: select at least 2 lines", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	local skel = get_skeleton(lines[1])
	for idx, line in ipairs(lines) do
		if get_skeleton(line) ~= skel then
			vim.notify(string.format("orderRising: line %d has different structure", start_line + idx - 1), vim.log.levels.ERROR)
			return
		end
	end

	-- Bottom line (end_line) is baseline (delta=0). Lines going up get delta = distance from bottom.
	for i = 1, end_line - start_line do
		increment_line_blocks(end_line - i, i)
	end
end

-- Normal mode: duplicate line below, then increment all number blocks in the original by 1.
local function order_rising_normal()
	local lnum = vim.fn.line('.')
	vim.cmd('normal! yyp')
	vim.api.nvim_win_set_cursor(0, { lnum, 0 })
	increment_line_blocks(lnum, 1)
end

K('v', '<Space>mo', '<esc><cmd>lua OrderRisingVisual()<cr>', { desc = "orderRising: number blocks in selection" })
K('n', '<Space>mo', order_rising_normal, { desc = "orderRising: duplicate line and bump numbers" })
