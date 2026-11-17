return {
	"ziontee113/color-picker.nvim",
	cmd = { "PickColor", "PickColorInsert", "ConvertHEXandRGB", "ConvertHEXandHSL" },
	config = function()
		require("color-picker").setup()
	end
}
