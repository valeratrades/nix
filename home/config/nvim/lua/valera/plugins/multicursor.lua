return require "lazier" {
	-- https://github.com/jake-stewart/multicursor.nvim
	"jake-stewart/multicursor.nvim",
	branch = "1.0",
	config = function()
		local mc = require("multicursor-nvim")
		mc.setup()

		-- only active while cursors exist, so these may shadow base maps
		mc.addKeymapLayer(function(set)
			set({ "n", "x" }, "<Left>", mc.prevCursor)
			set({ "n", "x" }, "<Right>", mc.nextCursor)
			set({ "n", "x" }, "<Space>x", mc.deleteCursor)
			set("n", "<Esc>", function()
				if not mc.cursorsEnabled() then
					mc.enableCursors()
				else
					mc.clearCursors()
				end
			end)
		end)

		K({ "n", "x" }, "<Up>", function() mc.lineAddCursor(-1) end, { desc = "Multicursor: add above" })
		K({ "n", "x" }, "<Down>", function() mc.lineAddCursor(1) end, { desc = "Multicursor: add below" })
		K({ "n", "x" }, "<Space><Up>", function() mc.lineSkipCursor(-1) end, { desc = "Multicursor: skip above" })
		K({ "n", "x" }, "<Space><Down>", function() mc.lineSkipCursor(1) end, { desc = "Multicursor: skip below" })
		K({ "n", "x" }, "<C-q>", mc.toggleCursor, { desc = "Multicursor: toggle (disabled cursors stay put)" })
		K("n", "<C-LeftMouse>", mc.handleMouse, { desc = "Multicursor: add at click" })
		K("n", "<C-LeftDrag>", mc.handleMouseDrag, { desc = "Multicursor: drag" })
		K("n", "<C-LeftRelease>", mc.handleMouseRelease, { desc = "Multicursor: release" })

		K({ "n", "x" }, "<Space>mn", function() mc.matchAddCursor(1) end, { desc = "Multicursor: add next match" })
		K({ "n", "x" }, "<Space>mN", function() mc.matchAddCursor(-1) end, { desc = "Multicursor: add prev match" })
		K({ "n", "x" }, "<Space>ms", function() mc.matchSkipCursor(1) end, { desc = "Multicursor: skip next match" })
		K({ "n", "x" }, "<Space>mS", function() mc.matchSkipCursor(-1) end, { desc = "Multicursor: skip prev match" })
		K({ "n", "x" }, "<Space>A", mc.matchAllAddCursors, { desc = "Multicursor: add on every match" })
		K({ "n", "x" }, "<Space>ma", mc.addCursorOperator, { desc = "Multicursor: add over motion" })
		K({ "n", "x" }, "<Space>M", mc.operator, { desc = "Multicursor: match in motion" })
		K({ "n", "x" }, "<Space>mr", mc.restoreCursors, { desc = "Multicursor: restore last" })
		K({ "n", "x" }, "<Space>md", mc.duplicateCursors, { desc = "Multicursor: duplicate" })
		K("n", "<Space>ml", mc.alignCursors, { desc = "Multicursor: align columns" })
		K("x", "<Space>mm", mc.matchCursors, { desc = "Multicursor: regex match in selection" })
		K("x", "<Space>mp", mc.splitCursors, { desc = "Multicursor: split selection by regex" })
		K("x", "<Space>mi", mc.insertVisual, { desc = "Multicursor: insert at each line" })
		K("x", "<Space>me", mc.appendVisual, { desc = "Multicursor: append at each line" })
		K("x", "<Space>mt", function() mc.transposeCursors(1) end, { desc = "Multicursor: rotate selections" })
	end,
}
