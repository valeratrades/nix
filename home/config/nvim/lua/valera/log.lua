-- Currently is specifically made for [rust](<https://github.com/rust-lang/rust>) and [tracing](<https://crates.io/crates/tracing>).
local utils = require("valera.utils")
local rp = require('rust_plugins')

local function copyDestination()
	local current_line = vim.api.nvim_get_current_line()
	local destination, _ = rp.parse_log_line(current_line)
	vim.fn.setreg("+", destination)
end

local function popupExpandedLog()
	local current_line = vim.api.nvim_get_current_line()
	local _, contents = rp.parse_log_line(current_line)
	if contents == nil then
		vim.api.nvim_err_writeln("No contents found in log line")
		return
	end
	rp.popup_log_contents(contents)
end

local function popupSelectedLog()
	local selection = utils.GetVisualSelection()
	rp.popup_log_contents(selection)
end

-- Named "Tracing" because 'l' for "log" is already taken by lsp
K("n", "<Space>ty", function() copyDestination() end, { desc = "Tracing: yank destination" })
K("n", "<Space>tp", function() popupExpandedLog() end, { desc = "Tracing: prettify log line" })
K("v", "<Space>tp", function() popupSelectedLog() end, { desc = "Tracing: prettify selection" })
