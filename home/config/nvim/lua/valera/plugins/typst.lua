return {
	--'kaarmu/typst.vim',
	'valeratrades/typst.vim',
	--XXX: does not work. Idea is to switch it from generating the pdf next to the source, to having it litter somewhere in /tmp/typ
	config = function()
		vim.schedule(function()
			pcall(vim.api.nvim_del_user_command, 'TypstWatch')
			vim.api.nvim_create_user_command('TypstWatch', function(opts)
				local input = opts.args ~= '' and vim.fn.fnamemodify(opts.args, ':p') or vim.api.nvim_buf_get_name(0)
				if input == '' then return end
				local outdir = '/tmp/typ'
				vim.fn.mkdir(outdir, 'p')
				local outfile = outdir .. '/' .. vim.fn.fnamemodify(input, ':t:r') .. '.pdf'
				vim.fn.jobstart({ 'typst', 'watch', input, '-o', outfile }, { detach = true })
			end, { nargs = '?' })
		end)
	end,
}
