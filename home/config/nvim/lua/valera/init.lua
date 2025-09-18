-- Suppress lspconfig deprecation warnings
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

require("valera.shorthands")
require("valera.utils")
-- above could be used from other internal modules too

require("valera.remap")
require("valera.lazy")
require("valera.opts")
require("valera.temporary")
require("valera.macros")
require("valera.rooter")
require("valera.autocommands")

require("valera.catpuccin")
