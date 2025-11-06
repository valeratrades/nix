-- Auto-rebuild Rust plugins if needed
local ok, rust_plugins = pcall(require, 'rust_plugins')
if not ok then
	-- First time setup - plugin doesn't exist, force build synchronously
	print("Rust plugins not found, building...")
	vim.fn.system('cd ' .. vim.fn.stdpath('config') .. '/rust_plugins && nix build')
	print("✓ Rust plugins built")
else
	-- Plugin exists, check if rebuild needed (async)
	vim.defer_fn(function()
		if rust_plugins.rebuild_if_needed then
			vim.fn.jobstart('true', {
				on_exit = function()
					rust_plugins.rebuild_if_needed()
				end
			})
		end
	end, 0)
end

-- Create symlink to rust_plugins.so if it doesn't exist or is a regular file
local lua_so_path = vim.fn.stdpath('config') .. '/lua/rust_plugins.so'
local result_so_path = vim.fn.stdpath('config') .. '/rust_plugins/result/lib/rust_plugins.so'
local is_symlink = vim.fn.getftype(lua_so_path) == 'link'
local exists = vim.fn.filereadable(lua_so_path) == 1

if not is_symlink and (not exists or vim.fn.getftype(lua_so_path) == 'file') then
	vim.fn.system(string.format('ln -sf %s %s', result_so_path, lua_so_path))
end

require("valera")
