return require "lazier" {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-fzf-native.nvim",
		"nvim-telescope/telescope-media-files.nvim",
		"nvim-telescope/telescope-ui-select.nvim",
		"olimorris/persisted.nvim",
		"nvim-telescope/telescope-dap.nvim",
	},
	config = function()
		local builtin = require('telescope.builtin')
		local actions = require('telescope.actions')
		local action_state = require('telescope.actions.state')

		-- Get git submodule paths from .gitmodules file
		local function get_submodule_paths()
			local gitmodules_path = vim.fn.findfile('.gitmodules', '.;')
			if gitmodules_path == '' then
				return {}
			end
			local paths = {}
			local content = vim.fn.readfile(gitmodules_path)
			for _, line in ipairs(content) do
				local path = line:match('%s*path%s*=%s*(.+)')
				if path then
					-- Add both the directory and all its contents
					table.insert(paths, path .. "/")
				end
			end
			return paths
		end

		-- Build file_ignore_patterns with submodules excluded
		local base_ignore_patterns = { ".git/", "target/", "%.lock" }
		local include_submodules = false -- toggle state

		local function build_ignore_patterns()
			local patterns = vim.tbl_extend("force", {}, base_ignore_patterns)
			if not include_submodules then
				local submodule_paths = get_submodule_paths()
				for _, path in ipairs(submodule_paths) do
					table.insert(patterns, path)
				end
			end
			return patterns
		end

		-- Build glob exclusions for the find command (fd/rg level, not post-filter)
		local function build_find_command_args()
			local args = {}
			if not include_submodules then
				local submodule_paths = get_submodule_paths()
				for _, path in ipairs(submodule_paths) do
					-- Remove trailing slash for glob pattern
					local clean_path = path:gsub("/$", "")
					table.insert(args, "--glob")
					table.insert(args, "!" .. clean_path .. "/**")
				end
			end
			return args
		end

		local function get_gs()
			local extra_args = build_find_command_args()
			return {
				hidden = true,
				no_ignore = true,
				file_ignore_patterns = build_ignore_patterns(),
				-- For find_files (uses fd by default)
				find_command = vim.list_extend(
					{ "fd", "--type", "f", "--hidden", "--no-ignore", "--color", "never" },
					extra_args
				),
				-- For live_grep (uses rg)
				additional_args = function()
					return extra_args
				end,
			}
		end
		-- note: `^` and `.` in file_ignore_patterns don't really work

		-- image.nvim integration for telescope preview (lazy-loaded)
		local supported_images = { "svg", "png", "jpg", "jpeg", "gif", "webp", "avif" }
		local image_api = nil -- lazy loaded
		local is_image_preview = false
		local image = nil
		local last_file_path = ""

		local is_supported_image = function(filepath)
			local split_path = vim.split(filepath:lower(), ".", { plain = true })
			local extension = split_path[#split_path]
			return vim.tbl_contains(supported_images, extension)
		end

		local delete_image = function()
			if not image then return end
			image:clear()
			is_image_preview = false
		end

		local create_image = function(filepath, winid, bufnr)
			if not image_api then
				require("lazy").load({ plugins = { "image.nvim" } })
				image_api = require("image")
			end
			image = image_api.hijack_buffer(filepath, winid, bufnr)
			if not image then return end
			vim.schedule(function()
				image:render()
			end)
			is_image_preview = true
		end

		local image_buffer_previewer_maker = function(filepath, bufnr, opts)
			if is_image_preview and last_file_path ~= filepath then
				delete_image()
			end
			last_file_path = filepath
			if is_supported_image(filepath) then
				create_image(filepath, opts.winid, bufnr)
			else
				require("telescope.previewers").buffer_previewer_maker(filepath, bufnr, opts)
			end
		end

		-- Toggle regex mode for telescope picker
		local function toggle_regex_mode(prompt_bufnr)
			local picker = action_state.get_current_picker(prompt_bufnr)
			local finder = picker.finder

			if finder.__regex_mode then
				finder.__regex_mode = false
				finder.opts = finder.opts or {}
				finder.opts.additional_args = finder.__original_additional_args
				vim.notify("Fuzzy mode", vim.log.levels.INFO)
			else
				finder.__regex_mode = true
				finder.opts = finder.opts or {}
				finder.__original_additional_args = finder.opts.additional_args
				finder.opts.additional_args = function(opts)
					local args = {}
					if finder.__original_additional_args then
						args = finder.__original_additional_args(opts) or {}
					end
					table.insert(args, "--fixed-strings")
					return args
				end
				vim.notify("Exact match mode", vim.log.levels.INFO)
			end

			-- Get current prompt and refresh
			local current_prompt = picker:_get_prompt()
			picker:refresh(finder, { reset_prompt = false })
			-- Restore the prompt text after refresh
			vim.schedule(function()
				local prompt_bufnr_new = picker.prompt_bufnr
				if prompt_bufnr_new and vim.api.nvim_buf_is_valid(prompt_bufnr_new) then
					vim.api.nvim_buf_set_lines(prompt_bufnr_new, 0, 1, false, { current_prompt })
					vim.api.nvim_win_set_cursor(0, { 1, #current_prompt })
				end
			end)
		end

		-- Toggle submodule visibility in telescope picker
		local function toggle_submodules(prompt_bufnr)
			include_submodules = not include_submodules
			local picker = action_state.get_current_picker(prompt_bufnr)

			local status = include_submodules and "Showing submodules" or "Hiding submodules"
			vim.notify(status, vim.log.levels.INFO)

			-- Close and reopen with new settings (finder options can't be modified in-place for find_command)
			local current_prompt = picker:_get_prompt()
			actions.close(prompt_bufnr)
			vim.schedule(function()
				-- Determine which picker was being used based on the prompt title or finder type
				local opts = vim.tbl_extend("force", get_gs(), { default_text = current_prompt })
				builtin.find_files(opts)
			end)
		end

		-- Custom action to send to quickfix and open replacer
		local function send_to_qf_and_replacer(prompt_bufnr)
			actions.send_to_qflist(prompt_bufnr)
			actions.open_qflist(prompt_bufnr)
			vim.defer_fn(function()
				require('replacer').run()
			end, 50)
		end

		-- Custom action to open parent directory of selected file
		local function open_parent_dir(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			if not entry then
				return
			end

			local path = entry.path or entry.filename or entry.value
			local parent = vim.fn.fnamemodify(path, ':h')
			actions.close(prompt_bufnr)
			vim.cmd('edit ' .. vim.fn.fnameescape(parent))
		end

		K('n', '<space>f', function() builtin.find_files(get_gs()) end, { desc = "Search files" })
		K('n', '<space>z', function() builtin.live_grep(get_gs()) end, { desc = "Live grep" })
		K('n', '<space>Z', function()
			local search_dir = nil
			local alt_buf = vim.fn.bufnr('#')
			if alt_buf ~= -1 and vim.bo[alt_buf].filetype == 'oil' then
				search_dir = require('oil').get_current_dir(alt_buf)
			else
				local file = vim.fn.expand('%:p')
				if file ~= '' then
					search_dir = vim.fn.fnamemodify(file, ':h')
				end
			end
			if not search_dir then
				vim.notify("No directory found", vim.log.levels.WARN)
				return
			end
			local opts = vim.tbl_extend("force", get_gs(), { cwd = search_dir })
			builtin.live_grep(opts)
		end, { desc = "Live grep (oil/file dir)" })
		K({ 'n', 'v' }, '<space>ss', function() builtin.grep_string(get_gs()) end,
			{ desc = "Grep visual selection or word under cursor" })
		K('n', '<space>sk', function() builtin.keymaps(get_gs()) end, { desc = "Keymaps" })
		K('n', '<space>sg', function() builtin.git_files(get_gs()) end, { desc = "Git files" })
		K('n', '<space>sp', "<cmd>Telescope persisted<cr>", { desc = "Persisted: sessions" })
		K('n', '<space>sb', function() builtin.buffers(get_gs()) end, { desc = "Find buffers" })
		K('n', '<space>sh', function() builtin.help_tags(get_gs()) end, { desc = "Neovim documentation" })
		K('n', '<space>sl', function() builtin.loclist(get_gs()) end, { desc = "Telescope loclist" })
		K('n', '<space>sn', function() builtin.find_files({ hidden = true, no_ignore_parent = true }) end,
			{ desc = "No_ignore_parent" })
		K('n', '<space>st', function()
			require('rust_plugins').find_todo()
			require('telescope.builtin').quickfix({ wrap_results = true, fname_width = 999 })
		end, { desc = "Project's TODOs" })
		K('n', '<space>si', "<cmd>Telescope media_files<cr>", { desc = "Media files" })
		K("n", "<C-f>", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { desc = "Effectively Ctrl+f", overwrite = true })

		local telescope = require("telescope")
		--TODO!!!!: package it properly for nix, then provide to the nvim wrapper
		--FUCK: requires to explicitly:
		--```sh
		--cd $XDG_DATA_HOME/nvim/lazy/telescope-fzf-native.nvim
		--make
		--```
		telescope.load_extension('fzf')
		local fzf_opts = {
			fuzzy = true,                  -- false will only do exact matching
			override_generic_sorter = true, -- override the generic sorter
			override_file_sorter = true,   -- override the file sorter
			case_mode = "smart_case",      -- or "ignore_case" or "respect_case"
		}

		telescope.setup {
			pickers = {
				lsp_dynamic_workspace_symbols = {
					sorter = telescope.extensions.fzf.native_fzf_sorter(fzf_opts)
				},
			},
			extensions = {
				media_files = {
					filetypes = { "png", "webp", "jpg", "jpeg" },
					find_cmd = "rg"
				},
				--["ui-select"] = {
				--	require("telescope.themes").get_dropdown {
				--		-- even more opts
				--	}
				--
				--	-- pseudo code / specification for writing custom displays, like the one
				--	-- for "codeactions"
				--	-- specific_opts = {
				--	--   [kind] = {
				--	--     make_indexed = function(items) -> indexed_items, width,
				--	--     make_displayer = function(widths) -> displayer
				--	--     make_display = function(displayer) -> function(e)
				--	--     make_ordinal = function(e) -> string
				--	--   },
				--	--   -- for example to disable the custom builtin "codeactions" display
				--	--      do the following
				--	--   codeactions = false,
				--	-- }
				--},
			},
			defaults = {
				buffer_previewer_maker = image_buffer_previewer_maker,
				mappings = {
					--Can't find action.top there, could this be done?
					i = {
						--TODO!!!: figure out how to do/immitate actions.top
						["<CR>"] = actions.select_default + actions.center,
						["<C-x>"] = actions.select_horizontal + actions.center,
						["<C-v>"] = actions.select_vertical + actions.center,
						["<C-t>"] = actions.select_tab + actions.center,
						["<C-l>"] = actions.select_all + actions.add_selected_to_loclist,
						["<c-f>"] = actions.to_fuzzy_refine,
						["<C-r>"] = send_to_qf_and_replacer,
						["<C-o>"] = open_parent_dir,
						["<C-g>"] = toggle_regex_mode,
						["<C-s>"] = toggle_submodules,
					},
					n = {
						["<CR>"] = actions.select_default + actions.center,
						["<C-x>"] = actions.select_horizontal + actions.center,
						["<C-v>"] = actions.select_vertical + actions.center,
						["<C-t>"] = actions.select_tab + actions.center,
						["<C-l>"] = actions.select_all + actions.add_selected_to_loclist,
						["<C-r>"] = send_to_qf_and_replacer,
						["<C-o>"] = open_parent_dir,
						["<C-g>"] = toggle_regex_mode,
						["<C-s>"] = toggle_submodules,
					}
				},
				layout_config = {
					width = 9999,
					height = 9999,
				}
			},
		}
		-- # TODO
		-- #TODO
		--
		-- Must be loaded strictly _after_ setup
		require("telescope").load_extension("media_files")
		require("telescope").load_extension("ui-select")

		--Q: should probably split by priority. Where "dbg" and "TEST" are actually the highest ones. Just include in the same `!` framework, have them wegh 11 and 10 respectively.
		K('n', '<space>sd', function()
			local base = get_gs()
			local submodule_args = base.additional_args and base.additional_args() or {}
			local gs_ext = vim.tbl_extend("force", base, {
				default_text = [[#\s*TEST|#\s*dbg|dbg!\(|#\s*Q|#\s*DEPRECATE|#\sDO|#\s*TODO|dbg]],
				additional_args = function()
					return vim.list_extend({ '--pcre2' }, submodule_args)
				end
			})
			builtin.live_grep(gs_ext)
		end, { desc = "Find Temporary" })

		-- Default mappings reference {{{
		--<C-n>/<Down>	Next item
		--<C-p>/<Up>	Previous item
		--j/k	Next/previous (in normal mode)
		--<cr>	Confirm selection
		--<C-q>	Confirm selection and open quickfix window
		--<C-x>	Go to file selection as a split
		--<C-v>	Go to file selection as a vsplit
		--<C-t>	Go to a file in a new tab
		--<C-u>	Scroll up in preview window
		--<C-d>	Scroll down in preview window
		--<C-/>/?	Show picker mappings (in insert & normal mode, respectively)
		--<C-c>	Close telescope
		--<Esc>	Close telescope (in normal mode)
		-- }}}
	end,
}
