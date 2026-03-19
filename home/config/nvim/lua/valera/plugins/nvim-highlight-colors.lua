return require "lazier" {
	"brenoprata10/nvim-highlight-colors",
	lazy = false, -- monkey-patching modules is incompatible with lazier's recorder proxies
	config = function()
		-- Patch in oklch() color recognition: oklch(0.80, 0.08, 95)
		do
			local color_utils = require("nvim-highlight-colors.color.utils")
			local buffer_utils = require("nvim-highlight-colors.buffer_utils")
			local rp = require("rust_plugins")

			local oklch_regex = "oklch%(%s*%d*%.?%d+%s*,%s*%d*%.?%d+%s*,%s*%-?%d*%.?%d+%s*%)"

			-- Inject oklch pattern into the detection pipeline
			local orig_get_positions = buffer_utils.get_positions_by_regex
			function buffer_utils.get_positions_by_regex(patterns, ...)
				local extended = { unpack(patterns) }
				extended[#extended + 1] = oklch_regex
				return orig_get_positions(extended, ...)
			end

			-- Teach the color resolver to handle oklch matches
			local orig_get_color_value = color_utils.get_color_value
			function color_utils.get_color_value(color, ...)
				if string.match(color, oklch_regex) then
					local vals = {}
					for v in string.gmatch(color, "%-?%d*%.?%d+") do
						vals[#vals + 1] = tonumber(v)
					end
					if #vals >= 3 then
						return rp.oklch(vals[1], vals[2], vals[3])
					end
				end
				return orig_get_color_value(color, ...)
			end
		end

		require("nvim-highlight-colors").setup({
			render = 'background',
			enable_named_colors = true,
			enable_tailwind = false,
		})
	end
}
