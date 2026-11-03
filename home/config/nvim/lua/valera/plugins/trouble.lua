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
				for _, v in ipairs(View.get({ mode = "symbols", open = true })) do
					if v.view.anchor == cur or v.view.win.win == cur then
						return v.view:close()
					end
				end

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
	},
}
