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

require("valera")
