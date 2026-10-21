-- Aligns top-level `&` of multi-line math blocks into columns. Rows are split on `\`, not on newlines.
-- Even columns are padded on the left and odd ones on the right, mirroring typst's own right/left alternation.

local function width_since_newline(s)
	return vim.fn.strdisplaywidth(s:match("[^\n]*$"))
end

-- a single space stands in for any run of spaces; newlines are kept
local function squash(ws)
	if ws:find("\n") then return (ws:gsub("[ \t]+\n", "\n")) end
	return ws == "" and "" or " "
end

local function split_prefix(s)
	local i = 1
	while true do
		local j = s:match("^%s*()", i)
		j = s:match("^//[^\n]*()", j) or j
		if j == i then break end
		i = j
	end
	return s:sub(1, i - 1), s:sub(i)
end

local function render_block(text, opening_line, seps)
	local rows, cells, from = {}, {}, 1
	for _, sep in ipairs(seps) do
		cells[#cells + 1] = text:sub(from, sep.offset - 1)
		from = sep.offset + 1
		if sep.kind == "linebreak" then
			rows[#rows + 1] = cells
			cells = {}
		end
	end
	cells[#cells + 1] = text:sub(from)
	rows[#rows + 1] = cells

	local out, cols = {}, 0
	for r, row in ipairs(rows) do
		local prefix, rest = split_prefix(row[1])
		if r > 1 and not prefix:find("\n") and (rest ~= "" or #row > 1) then return nil end -- rows sharing a line can't be aligned independently
		prefix = prefix:gsub("[ \t]+\n", "\n")
		if prefix:find("\n") then prefix = prefix:gsub("[ \t]*$", "") .. opening_line:match("^[ \t]*") end -- existing indent is stale padding
		row[1] = rest
		out[r] = (r == 1 and not prefix:find("\n")) and { pre = vim.fn.strdisplaywidth(opening_line), s = prefix } or { pre = 0, s = prefix }
		cols = math.max(cols, #row - 1)
	end

	local function parts(cell, is_last_of_block)
		local lead, core, trail = cell:match("^(%s*)(.-)(%s*)$")
		return squash(lead), core, is_last_of_block and trail:gsub("[ \t]+\n", "\n") or squash(trail)
	end

	for k = 1, cols do
		local target, pending = 0, {}
		for r, row in ipairs(rows) do
			if #row > k then
				local lead, core, trail = parts(row[k], false)
				local col = out[r].pre + width_since_newline(out[r].s .. lead .. core .. trail)
				target = math.max(target, col)
				pending[r] = { lead, core, trail, col }
			end
		end
		for r, p in pairs(pending) do
			local lead, core, trail, col = p[1], p[2], p[3], p[4]
			local pad = (" "):rep(target - col)
			local s
			if (k % 2 == 1) and not (core .. trail):find("\n") then
				s = lead .. pad .. core .. trail
			elseif not trail:find("\n") then
				s = lead .. core .. pad .. trail
			else
				s = lead .. core .. trail .. pad
			end
			out[r].s = out[r].s .. s .. "&"
		end
	end

	local res = {}
	for r, row in ipairs(rows) do
		local lead, core, trail = parts(row[#row], r == #rows)
		res[r] = out[r].s .. lead .. core .. trail
	end
	return table.concat(res, "\\")
end

return function(buf)
	local tree = vim.treesitter.get_parser(buf, "typst"):parse()[1]
	local query = vim.treesitter.query.parse("typst", "(math) @m")
	local edits = {}
	for _, math in query:iter_captures(tree:root(), buf) do
		local nested = false
		local p = math:parent()
		while p do
			if p:type() == "math" then nested = true end
			p = p:parent()
		end
		local open, formula, close = math:child(0), math:child(1), math:child(math:child_count() - 1)
		if not nested and formula and formula:type() == "formula" and math:start() ~= select(3, math:range()) then
			local _, _, sr, sc = open:range()
			local er, ec = close:range()
			local lines = vim.api.nvim_buf_get_text(buf, sr, sc, er, ec, {})
			local line_offsets, acc = {}, 0
			for i, l in ipairs(lines) do
				line_offsets[sr + i - 1] = acc - (i == 1 and sc or 0)
				acc = acc + #l + 1
			end
			local seps = {}
			for child in formula:iter_children() do
				local t = child:type()
				if t == "align" or t == "linebreak" then
					local row, col = child:range()
					seps[#seps + 1] = { kind = t, offset = line_offsets[row] + col + 1 }
				end
			end
			local has_align = vim.iter(seps):any(function(s) return s.kind == "align" end)
			if has_align then
				local text = table.concat(lines, "\n")
				local line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, true)[1]
				local new = render_block(text, line:sub(1, sc), seps)
				if new and new ~= text then
					edits[#edits + 1] = { sr, sc, er, ec, vim.split(new, "\n") }
				end
			end
		end
	end
	for i = #edits, 1, -1 do
		local e = edits[i]
		vim.api.nvim_buf_set_text(buf, e[1], e[2], e[3], e[4], e[5])
	end
end
