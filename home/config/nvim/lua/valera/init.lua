---- Suppress noisy notifications //NB: make sure to load this **before** the stuff that produces errors we're trying to suppress at eval time. Sounds obvious, but I debugged this for a very long time once
local original_notify = vim.notify
local suppressed_log = vim.fn.stdpath("log") .. "/suppressed_notify.log"
vim.notify = function(msg, level, opts)
	if type(msg) == "string" then
		-- lspconfig deprecation warnings
		if msg:match("require.*lspconfig.*framework.*deprecated") or
				msg:match("Feature will be removed in nvim%-lspconfig") then
			return
		end
		-- rust-analyzer workspace discovery errors (standalone .rs files)
		if msg:match("rust%-analyzer health status is %[error%]") or
				msg:match("Failed to discover workspace") or
				msg:match("Failed to load workspaces") or
				msg:match("No project root found") or
				msg:match("Starting rust%-analyzer client in detached/standalone mode") then
			-- log to file instead of interrupting
			local f = io.open(suppressed_log, "a")
			if f then
				f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg:gsub("\n", " ") .. "\n")
				f:close()
			end
			vim.api.nvim_echo({ { "RA: workspace error (see :RustLsp logFile)", "WarningMsg" } }, false, {})
			return
		end
	end
	return original_notify(msg, level, opts)
end
--
---- Also suppress vim.deprecate warnings for lspconfig (nvim 0.11+)
--local original_deprecate = vim.deprecate
--vim.deprecate = function(name, alternative, version, plugin, backtrace)
--	if plugin == "nvim-lspconfig" then
--		return
--	end
--	return original_deprecate(name, alternative, version, plugin, backtrace)
--end
--
require("valera.shorthands")
require("valera.utils")
-- above could be used from other internal modules too

require("valera.remap")
require("valera.lazy")
require("valera.lsp")
require("valera.log")
require("valera.opts")
require("valera.autocommands")
require("valera.termfilechooser")

require("valera.catpuccin")
