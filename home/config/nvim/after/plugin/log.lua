-- Currently is specifically made for [rust](<https://github.com/rust-lang/rust>) and [tracing](<https://crates.io/crates/tracing>).
local utils = require("valera.utils")

--- Parses a log line, assuming one of the following formats:
--- - `[indent] in [destination] with [contents]`
--- - `[indent] at [destination]`
--- -TODO: `[indent] [datetime] [TRACE | DEBUG | INFO | WARN | ERROR] [destination]: [contents]`
--- @param log_line string The log line to parse.
--- @return string | nil destination The destination part of the log line.
--- @return string | nil contents The contents part of the log line.
local function parseLogLine(log_line)
	if log_line:match("in%s+([%w_:]+)%s+with") then
		local destination = log_line:match("in%s+([%w_:]+)%s+with")
		local contents = log_line:match("with%s+(.+)")
		return destination, contents
	elseif log_line:match("at%s+([%w_/]+%.rs:%d+)") then
		local destination = log_line:match("at%s+([%w_/]+%.rs:%d+)")
		return destination, nil
	elseif log_line:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s+[A-Z]+%s+([%w_:]+):%s+(.+)") then
		local destination, contents = log_line:match(
			"%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s+[A-Z]+%s+([%w_:]+):%s+(.+)")
		return destination, contents
	else
		return nil, nil
	end
end

local function copyDestination()
	local current_line = vim.api.nvim_get_current_line()
	local destination, _ = parseLogLine(current_line)
	vim.fn.setreg("+", destination)
end

vim.keymap.set("n", "<Space>ty", function() copyDestination() end, { desc = "+y log-line's destination" })

---@param contents string
local function popupLogContents(contents)
	local handle = io.popen("command -v prettify_log")
	local result = handle:read("*a")
	handle:close()
	if result == "" then
		vim.api.nvim_err_writeln(
			"prettify_log not found in PATH. [Install it from github](<https://github.com/valeratrades/prettify_log>)")
		return
	end

	local prettify_cmd = "cat <<EOF | prettify_log - --maybe-colon-nested\n" .. contents .. "\nEOF"
	local prettified = vim.fn.system(prettify_cmd)
	local as_rust_block = "```rs\n" .. prettified .. "```"
	utils.ShowMarkdownPopup(as_rust_block)
end

local function popupExpandedLog()
	local current_line = vim.api.nvim_get_current_line()
	local _, contents = parseLogLine(current_line)
	if contents == nil then
		vim.api.nvim_err_writeln("No contents found in log line")
		return
	end
	popupLogContents(contents)
end

vim.keymap.set("n", "<Space>tp", function() popupExpandedLog() end, { desc = "Popup with prettified log line" })


local function popupSelectedLog()
	local selection = utils.GetVisualSelection()
	popupLogContents(selection)
end

vim.keymap.set("v", "<Space>tp", function() popupSelectedLog() end, { desc = "Popup selection as prettyfied log" })
