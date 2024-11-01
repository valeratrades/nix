-- want to add `LEAN_PATH=/path/to/project/build/` to the `lean --run {path_to_file}` so I can import libraries, but no way to do so currently...

-- pretty sure none of this works for shit
vim.g.maplocalleader = '<Space>m'

require('lean').setup {
	mappings = true,
}
