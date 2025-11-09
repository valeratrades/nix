return require "lazier" { -- CamelCaseACRONYMWords_underscore1234
	--w --->w-->w----->w---->w-------->w->w
	--e -->e-->e----->e--->e--------->e-->e
	--b < ---b<--b<-----b<----b<--------b<-b
	'chaoren/vim-wordmotion',
	-- default prefix is already <Space>
	keys = {
		{ "<Space>w", mode = { "n", "v", "o", "x" } },
		{ "<Space>b", mode = { "n", "v", "o", "x" } },
		{ "<Space>e", mode = { "n", "v", "o", "x" } },
	},
}
