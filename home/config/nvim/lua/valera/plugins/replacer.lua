return {
	'gabrielpoca/replacer.nvim',
	opts = { rename_files = false },
	keys = {
		{
			'<space>h',
			function() require('replacer').run() end,
			desc = "run replacer.nvim"
		}
	}
}
