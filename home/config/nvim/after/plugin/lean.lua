-- want to add `LEAN_PATH=/path/to/project/build/` to the `lean --run {path_to_file}` so I can import libraries, but no way to do so currently...

vim.g.maplocalleader = '<Space>m' -- pretty sure this does not work

require('lean').setup {
	--TODO: write all keys explicitly
	mappings = true, --HACK: sets a bunch of stuff over maplocalleader
}

K("n", "<Space>ml", function() vim.cmd("Telescope loogle") end)
