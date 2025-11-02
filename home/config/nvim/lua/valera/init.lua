-- Suppress lspconfig deprecation warnings //NB: make sure to load this **before** the stuff that produces errors we're trying to suppress at eval time. Sounds obvious, but I debugged this for a very long time once
local original_notify = vim.notify
vim.notify = function(msg, level, opts)
	if type(msg) == "string" and (
				msg:match("require.*lspconfig.*framework.*deprecated") or
				msg:match("Feature will be removed in nvim%-lspconfig")
			) then
		return
	end
	return original_notify(msg, level, opts)
end

-- Also suppress vim.deprecate warnings for lspconfig (nvim 0.11+)
local original_deprecate = vim.deprecate
vim.deprecate = function(name, alternative, version, plugin, backtrace)
	if plugin == "nvim-lspconfig" then
		return
	end
	return original_deprecate(name, alternative, version, plugin, backtrace)
end

require("valera.shorthands")
require("valera.utils")
-- above could be used from other internal modules too

require("valera.remap")
require("valera.lazy")
require("valera.lsp")
require("valera.opts")
--require("valera.temporary")
require("valera.rooter")
require("valera.autocommands")

require("valera.catpuccin")
