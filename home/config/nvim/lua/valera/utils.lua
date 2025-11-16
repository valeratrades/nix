local M = {}

--- Finds the best match in a list by querying the last word of each element.
--- @param data table List of strings to search through, matching on the last word.
--- @param query string Query to search for
--- @return string|nil Best match or nil
--- @return string|nil error message
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
		if not fzf then
			return nil, "Failed to open fzf"
		end
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
