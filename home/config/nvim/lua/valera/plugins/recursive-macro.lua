return require "lazier" {
	--https://github.com/jake-stewart/recursive-macro.nvim
	"jake-stewart/recursive-macro.nvim",
	config = function()
		require("recursive-macro").setup({
			registers = { "q", "w", "e", "r", "t", "y" },
			startMacro = "q",
			replayMacro = "Q",
		})
	end,
	-- Jake himself does have different though:
	--return {
	--	"jake-stewart/recursive-macro.nvim",
	--	keys = "q",
	--	config = function()
	--		require("recursive-macro").setup()
	--	end
	--}
	--? does it not have support for multiple registers anymore?
}
