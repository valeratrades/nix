-- Auto-build Rust plugins on startup (only if changed)
local function should_rebuild_rust_plugins()
	local rust_dir = vim.fn.stdpath('config') .. '/rust_plugins'
	local state_dir = vim.fn.stdpath('state') .. '/rust_plugins'
	local timestamp_file = state_dir .. '/last_build'

	-- Create state directory if it doesn't exist
	vim.fn.mkdir(state_dir, 'p')

	-- Get last build time
	local last_build_time = 0
	local f = io.open(timestamp_file, 'r')
	if f then
		last_build_time = tonumber(f:read('*all')) or 0
		f:close()
	end

	-- Check if any files in rust_plugins have been modified since last build
	local find_cmd = string.format("find %s -type f -newer %s 2>/dev/null | head -1",
		vim.fn.shellescape(rust_dir), vim.fn.shellescape(timestamp_file))
	local modified_files = vim.fn.system(find_cmd)

	-- If timestamp file doesn't exist or files were modified, rebuild
	return last_build_time == 0 or vim.trim(modified_files) ~= ""
end

if should_rebuild_rust_plugins() then
	local rust_build_start = vim.loop.hrtime()
	local state_dir = vim.fn.stdpath('state') .. '/rust_plugins'
	local log_file = state_dir .. '/build.log'
	local timestamp_file = state_dir .. '/last_build'

	vim.fn.jobstart('cd ' .. vim.fn.stdpath('config') .. '/rust_plugins && nix build', {
		on_exit = function(_, exit_code)
			local elapsed_ms = (vim.loop.hrtime() - rust_build_start) / 1e6
			local timestamp = os.date('%Y-%m-%d %H:%M:%S')
			local status = exit_code == 0 and "SUCCESS" or "FAILED"
			local log_entry = string.format("[%s] Rust plugin build %s (%.0fms)\n", timestamp, status, elapsed_ms)

			-- Write to log
			local file = io.open(log_file, 'a')
			if file then
				file:write(log_entry)
				file:close()
			end

			-- Update timestamp on success
			if exit_code == 0 then
				local ts = io.open(timestamp_file, 'w')
				if ts then
					ts:write(tostring(os.time()))
					ts:close()
				end
			end
		end,
		stdout_buffered = true,
		stderr_buffered = true,
	})
end

require("valera")
