local M = {}

--- Makes a popup with the given text. Sets the filetype to `markdown` to allow for syntax highlighting.
function M.ShowMarkdownPopup(text)
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}
	for line in string.gmatch(text, "([^\n]+)") do
		table.insert(lines, line)
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = 0
	for _, line in ipairs(lines) do
		if #line > width then
			width = #line
		end
	end
	width = math.max(width + 4, 30) -- Add padding and ensure a minimum width

	local height = #lines + 2      -- Add padding to height

	local row = (vim.o.lines - height) / 2
	local col = (vim.o.columns - width) / 2

	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
		title = " Popup ",
		title_pos = "center",
		zindex = 50
	}

	local win = vim.api.nvim_open_win(buf, true, opts)
	vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { nowait = true, noremap = true, silent = true })

	vim.api.nvim_set_option_value('cursorline', true, { win = win })

	-- Set the buffer filetype to Markdown to allow for syntax highlighting
	vim.api.nvim_set_option_value('filetype', 'markdown', { scope = 'local', buf = buf })

	-- Get the actual width and height of the window
	local actual_width = vim.api.nvim_win_get_width(win)
	local actual_height = vim.api.nvim_win_get_height(win)

	print("Actual Width: " .. actual_width)
	print("Actual Height: " .. actual_height)
end

--- Finds the best match in a list by querying the last word of each element.
--- @param data table List of strings to search through, matching on the last word.
--- @return string|nil Best match or nil, string|nil error message.
function M.FzfBestMatch(data, query)
	local function get_last_slice(str)
		local slices = {}
		for word in str:gmatch("%S+") do
			table.insert(slices, word)
		end
		return slices[#slices]
	end

	local function fzf_filter_symbols(data, query)
		local filtered_data = {}
		for _, symbol in ipairs(data) do
			local last_slice = get_last_slice(symbol)
			if last_slice:match(query) then
				table.insert(filtered_data, symbol)
			end
		end

		if #filtered_data == 0 then
			return nil, "No match found"
		end

		local items = table.concat(filtered_data, "\n")
		local fzf = io.popen('echo "' .. items .. '" | fzf --filter="' .. query .. '"', 'r')
		local result = fzf:read("*all")
		fzf:close()

		if result == "" then
			return nil, "No match found"
		end

		return result:gsub("\n", ""), nil
	end

	return fzf_filter_symbols(data, query)
end

---@return string The visual selection
function M.GetVisualSelection()
	assert(vim.fn.mode() == 'v' or vim.fn.mode() == 'V' or vim.fn.mode() == '', "Not in visual mode")
	vim.cmd('normal! "xy')
	return vim.fn.getreg('x')
end

return M
