-- fork: upstream + re-edit of every buffer after the deferred start (non-current tabs missed FileType)
local lazierpath = vim.fn.stdpath("data") .. "/lazier/lazier.nvim"
if not vim.uv.fs_stat(lazierpath) then
	local out = vim.fn.system({ "git", "clone", "https://github.com/valeratrades/lazier.nvim.git", lazierpath })
	assert(vim.v.shell_error == 0, "cloning lazier.nvim: " .. out)
end
vim.opt.rtp:prepend(lazierpath)

-- lazy.nvim starts after the first frame (plain start when opening a dir); modules required in `before` get bundled
-- and bytecode-compiled. Spec changes recompile on next launch, and plugins' keymaps/autocmds/commands are recorded
-- into lazy triggers then, so plugin specs must not compute per-launch values in plain fields.
require("lazier").setup("valera.plugins", {
	lazier = {
		infer_events = "fallback", -- plugins with mappings/commands load on those, as specs here were tuned for
		before = function()
			require("valera.shorthands")
			require("valera.utils")
			require("valera.remap")
			require("valera.log")
			require("valera.opts")
			require("valera.lsp") -- sets vim.g.rustaceanvim, which must precede any plugin load
			require("valera.autocommands")
			require("valera.termfilechooser") -- `nvim file +TermFileChooserSave` runs its command before `after`
		end,
		after = function()
			require("valera.commit_view")
			require("valera.legacy")
			SetThemeSystem()
		end,
	},
	-- atm prefer to just install them through systemPackages, natively to nix
	rocks = {
		enabled = false,
	},
})
