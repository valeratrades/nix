local function find(pred)
	for _, v in ipairs(require("trouble.view").get({ mode = "symbols", open = true })) do
		if v.view.anchor and pred(v.view) then return v.view end
	end
end

return require "lazier" {
	"folke/trouble.nvim",
	opts = {
		modes = {
			symbols = {
				--auto_open = true, -- behaves inconsistently, have to do manually
				--auto_close = true, -- without `auto_open`, just nukes itself when navigating
				auto_refresh = true,
				warn_no_results = false,
				focus = false, -- don't focus on open
			},
		},
	},
	cmd = "Trouble",
	keys = {
		{
			"<space><space>x",
			function()
				local View = require("trouble.view")
				local Main = require("trouble.view.main")
				local cur = vim.api.nvim_get_current_win()
				local open = find(function(v) return v.anchor == cur or v.win.win == cur end)
				if open then return open:close() end

				local view = View.new(require("trouble.config").get({
					mode = "symbols",
					win = { relative = "win", position = "right", win = cur },
				}))
				view.anchor = cur
				-- trouble's `pinned` binds to a buffer and drops it on buffer switch; bind to the pane instead
				local function main(self)
					if not vim.api.nvim_win_is_valid(cur) then return end -- anchor pane closed; view is being torn down
					self._main = Main._info(cur)
					return self._main
				end
				view.main = main
				function view:on_mount()
					View.on_mount(self)
					vim.api.nvim_win_set_config(self.win.win, { focusable = false }) -- keeps it out of <C-w> nav; reached via <space><space>i
				end
				for _, s in ipairs(view.sections) do
					s.main = main
				end
				vim.api.nvim_create_autocmd("WinClosed", {
					pattern = tostring(cur),
					once = true,
					callback = function() vim.schedule(function() view:close() end) end, -- can't close windows inside WinClosed
				})
				view:open()
			end,
			desc = "Symbols (Trouble), per pane",
		},
		{
			"<space><space>i",
			function()
				local cur = vim.api.nvim_get_current_win()
				local view = find(function(v) return v.anchor == cur end)
				if not view then return vim.notify("No symbols view for this pane", vim.log.levels.WARN) end
				vim.api.nvim_set_current_win(view.win.win)
			end,
			desc = "Symbols (Trouble): enter pane's view",
		},
		{
			"<space><space>o",
			function()
				local cur = vim.api.nvim_get_current_win()
				local view = find(function(v) return v.win.win == cur end)
				if not view then return vim.notify("Not in a symbols view", vim.log.levels.WARN) end
				vim.api.nvim_set_current_win(view.anchor)
			end,
			desc = "Symbols (Trouble): back to parent pane",
		},
	},
}
