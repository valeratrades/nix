local rustaceanvim = require("rustaceanvim")

local capabilities = {
	general = {
		positionEncodings = {
			"utf-8",
			"utf-16",
			"utf-32"
		},
	},
}

vim.diagnostic.config({
	virtual_text = false,
	-- if line has say both a .HINT and .WARNING, the "worst" will be shown (as a sign on the left)
	severity_sort = true,
})

function ToggleDiagnostics()
	local state = vim.diagnostic.is_enabled()
	if state then
		vim.diagnostic.enable(false)
		-- I think it is semantically similar
		vim.opt.spell = false
	else
		vim.diagnostic.enable(true)
		vim.opt.spell = true
	end
end

function ToggleVirtualText()
	local config = vim.diagnostic.config
	local virtual_text = config().virtual_text

	if virtual_text then
		config({ virtual_text = false })
	else
		config({ virtual_text = true })
	end
end

--


local on_attach = function(client, bufnr)
	local telescope_builtin = require("telescope.builtin")

	local function buf_set_keymap(mode, lhs, rhs, opts)
		opts = opts or {}
		opts.buffer = bufnr
		K(mode, lhs, rhs, opts)
	end

	buf_set_keymap('n', 'K', vim.lsp.buf.hover, { desc = "Hover Info", overwrite = true })
	buf_set_keymap('n', 'gd', vim.lsp.buf.definition, { desc = "Go to Definition", overwrite = true })
	buf_set_keymap('n', '<space>lR', vim.lsp.buf.rename, { desc = "Rename" })
	buf_set_keymap('n', '<space>lh', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end,
		{ desc = "Toggle Inlay Hints" })

	buf_set_keymap('n', '<C-r>', function() require('rust_plugins').jump_to_diagnostic(1, 'max') end, { desc = "Next Error", overwrite = true })
	buf_set_keymap('n', '<C-n>', function() require('rust_plugins').jump_to_diagnostic(-1, 'max') end, { desc = "Previous Error" })
	-- would prefer to put next two on the same keys but `Shift`ed, but vim doesn't understand it with Ctrl atm
	buf_set_keymap('n', '<C-t>', function() require('rust_plugins').jump_to_diagnostic(1, 'all') end, { desc = "Next Diagnostic" })
	buf_set_keymap('n', '<C-s>', function() require('rust_plugins').jump_to_diagnostic(-1, 'all') end, { desc = "Previous Diagnostic" })

	buf_set_keymap('n', '<space>lD', vim.lsp.buf.declaration, { desc = "Declaration" })
	buf_set_keymap('n', '<space>lt', vim.lsp.buf.type_definition, { desc = "Type Definition" })
	buf_set_keymap('n', '<space>li', '<cmd>Telescope lsp_implementations<CR>', { desc = "Implementations" })
	buf_set_keymap('n', '<space>lr', '<cmd>Telescope lsp_references<CR>', { desc = "References" })
	buf_set_keymap('n', '<space>ld', function() telescope_builtin.diagnostics({ sort_by = "severity" }) end,
		{ desc = "Diagnostics" })
	buf_set_keymap('n', '<space>ll', function() telescope_builtin.diagnostics({ bufnr = 0, sort_by = "severity" }) end,
		{ desc = "Local Diagnostics" })

	-- -- Search Symbols
	--? should I make the base keymap for this shorter?
	local set_dynamic_symbols_keymap = function(key, symbols)
		local keymap = string.format('<space>l<space>%s', key)
		local desc = string.format("Dynamic Workspace Symbols: [%s]", symbols)

		local opts = {}
		opts.buffer = bufnr
		opts.desc = desc
		opts.silent = true -- doesn't work, telescope still warns when no searches were shown given query
		K('n', keymap, function() telescope_builtin.lsp_dynamic_workspace_symbols({ symbols = symbols }) end,
			opts)
	end
	--REF:
	-- dynamic_workspace_symbols: matches on [name] only
	-- workspace_symbols: matches on all of [destination, name, type]
	buf_set_keymap('n', '<space>lw', '<cmd>Telescope lsp_document_symbols<CR>', { desc = "Document Symbols" })
	buf_set_keymap('n', '<space>lW', function() telescope_builtin.lsp_dynamic_workspace_symbols() end,
		{ desc = "Dynamic Workspace Symbols" })
	buf_set_keymap('n', '<space>l<space>a',
		function() telescope_builtin.lsp_workspace_symbols() end,
		{ desc = "Workspace Symbols" })
	set_dynamic_symbols_keymap('f', { "function" })
	set_dynamic_symbols_keymap('s', { "struct" })
	set_dynamic_symbols_keymap('m', { "module" })
	set_dynamic_symbols_keymap('c', { "constant" })
	set_dynamic_symbols_keymap('e', { "enum" })
	set_dynamic_symbols_keymap('v', { "variable" })
	--

	buf_set_keymap('n', '<space>lz', '<cmd>Telescope lsp_incoming_calls<CR>', { desc = "Incoming Calls" })
	buf_set_keymap('n', '<space>lZ', '<cmd>Telescope lsp_outgoing_calls<CR>', { desc = "Outgoing Calls" })
	buf_set_keymap('n', '<space>lf', function() vim.lsp.buf.format({ async = true }) end, { desc = "Format" })
	buf_set_keymap({ 'n', 'v' }, '<space>la', vim.lsp.buf.code_action, { desc = "Code Action" })
	buf_set_keymap('n', '<space>ly', function() require('rust_plugins').yank_diagnostic_popup() end, { desc = "Yank Diagnostic Popup" })
	buf_set_keymap('n', '<space>ls', ToggleDiagnostics, { desc = "Toggle Diagnostics" })
	buf_set_keymap('n', '<space>lv', ToggleVirtualText, { desc = "Toggle Virtual Text" })
	buf_set_keymap('n', '<space>l2',
		'<cmd>lua vim.opt.shiftwidth=2<CR><cmd>lua vim.opt.tabstop=2<CR><cmd>lua vim.opt.expandtab=true<CR>',
		{ desc = "Tab = 2" })
	buf_set_keymap('n', '<space>l4',
		'<cmd>lua vim.opt.shiftwidth=4<CR><cmd>lua vim.opt.tabstop=4<CR><cmd>lua vim.opt.expandtab=true<CR>',
		{ desc = "Tab = 4" })
	buf_set_keymap('n', '<space>l8',
		'<cmd>lua vim.opt.shiftwidth=8<CR><cmd>lua vim.opt.tabstop=8<CR><cmd>lua vim.opt.expandtab=true<CR>',
		{ desc = "Tab = 8" })
	buf_set_keymap('n', '<space>l0',
		'<cmd>lua vim.opt.expandtab=false<CR><cmd>lua vim.opt.tabstop=2<CR><cmd>lua vim.opt.shiftwidth=2<CR><cmd>lua vim.opt.softtabstop=0<CR>',
		{ desc = "Reset Tab Settings" })


	if client.supports_method('textDocument/formatting') then
		if vim.fn.expand('%:e') ~= 'py' and vim.fn.expand('%:e') ~= 'nix' then
			require('lsp-format').on_attach(client)
		end
	end
end


-- these set a bunch of indent presets in a very weird manner; making consequences very difficult to debug {{{
vim.g.rust_recommended_style = false
vim.g.python_recommended_style = false
vim.g.golang_recommended_style = false
vim.g.cpp_recommended_style = false
--,}}}

-- Set default configuration for all LSP servers
vim.lsp.config('*', {
	capabilities = capabilities,
	on_attach = on_attach,
})

-- lua_ls
vim.lsp.config('lua_ls', {
	settings = {
		Lua = {
			runtime = {
				version = 'LuaJIT',
			},
			diagnostics = {
				globals = { 'vim' },
			},
			workspace = {
				library = vim.api.nvim_get_runtime_file("", true),
				checkThirdParty = false,
			},
			telemetry = {
				enable = false,
			},
		},
	},
})
vim.lsp.enable('lua_ls')

-- tailwindcss
vim.lsp.config('tailwindcss', {
	cmd = { 'tailwindcss-language-server', '--stdio' },
})
vim.lsp.enable('tailwindcss')

-- gopls
vim.lsp.config('gopls', {
	settings = {
		gopls = {
			completeUnimported = true,
			usePlaceholders = true,
			analyses = {
				unusedparams = true,
			},
			staticcheck = true,
		},
	},
})
vim.lsp.enable('gopls')

-- bashls
vim.lsp.config('bashls', {})
vim.lsp.enable('bashls')

-- clangd
vim.lsp.config('clangd', {})
vim.lsp.enable('clangd')

-- jsonls
vim.lsp.config('jsonls', {})
vim.lsp.enable('jsonls')

-- marksman
vim.lsp.config('marksman', {})
vim.lsp.enable('marksman')

-- nil_ls
vim.lsp.config('nil_ls', {
	settings = {
		formatter = { command = { "nixpkgs-fmt" } },
	},
})
vim.lsp.enable('nil_ls')

-- ocamllsp
vim.lsp.config('ocamllsp', {
	cmd = { 'ocamllsp' },
	settings = {
		formatter = { command = { "ocamlformat" } },
	},
})
vim.lsp.enable('ocamllsp')

-- typst
vim.lsp.config('tinymist', {
	settings = {
		--exportPdf = "onType",
		--outputPath = "/tmp/typ/$name", -- put PDFs in /tmp, instead of littering next to the source
		exportPdf = 'never', -- currently always using `TypstWatch` of `typst.vim`
	},
})
vim.lsp.enable('tinymist')

vim.lsp.config('csharp_ls', {
	settings = {
		csharp = {
			AutomaticWorkspaceInit = true,
		},
	},
})
vim.lsp.enable('csharp_ls')

-- python {{{
vim.lsp.config('ty', {
	settings = {
		ty = {
			experimental = {
				rename = true,
			},
		},
	},
})
vim.lsp.enable('ty')

vim.lsp.config('ruff', {})
vim.lsp.enable('ruff')
--,}}}

-- lean
--vim.lsp.config('lean', {
--	--capabilities = capabilities,
--	--filetypes = { "lean" }, --TEST
--	on_attach = function(client, bufnr)
--		on_attach(client, bufnr)
--		K("n", "<Space>ml", function() vim.cmd("Telescope loogle") end, { buffer = bufnr })
--	end,
--	init_options = {
--		editDelay = 250,
--	},
--})
--vim.lsp.enable('lean')

-- lean
require('lean').setup {
	--TODO: write all keys explicitly
	mappings = true, --HACK: sets a bunch of stuff over maplocalleader
	lsp = false,    -- disable deprecated lsp setup
}

vim.lsp.config('leanls', {
	on_attach = function(client, bufnr)
		on_attach(client, bufnr)
		K("n", "<Space>ml", function() vim.cmd("Telescope loogle") end, { buffer = bufnr, desc = "Lean: Loogle" })
	end,
	init_options = {
		editDelay = 250,
	},
})
vim.lsp.enable('leanls')

-- Rust configuration
local function codelldb_adapter()
	local extension_path = vim.env.HOME .. '/.vscode/extensions/vadimcn.vscode-lldb-1.10.0/'
	local codelldb_path = extension_path .. 'adapter/codelldb'
	local liblldb_path = extension_path .. 'lldb/lib/liblldb'
	local this_os = vim.uv.os_uname().sysname;

	if this_os:find "Windows" then
		codelldb_path = extension_path .. "adapter\\codelldb.exe"
		liblldb_path = extension_path .. "lldb\\bin\\liblldb.dll"
	else
		-- The liblldb extension is .so for Linux and .dylib for MacOS
		liblldb_path = liblldb_path .. (this_os == "Linux" and ".so" or ".dylib")
	end

	local cfg = require('rustaceanvim.config')
	return cfg.get_codelldb_adapter(codelldb_path, liblldb_path)
end

vim.g.rust_check_with = "clippy"
local function rustCheckWith(cmd)
	if cmd ~= "cargo" and cmd ~= "clippy" then
		vim.notify("Invalid command: " .. cmd, vim.log.levels.ERROR)
		return
	end

	vim.g.rust_check_with = cmd

	--HACK: Restart LSP to apply the new settings. Currently they don't accept functions for checkOnSave.command (2025/03/31)
	vim.cmd('LspRestart')
end
K("n", "<space>rwl", function() rustCheckWith("clippy") end, { desc = "Rust: switch to checking with `clippy`" })
K("n", "<space>rwe", function() rustCheckWith("check") end, { desc = "Rust: switch to checking with `check`" })

-- Call on_attach for all Rust files
vim.api.nvim_create_autocmd("FileType", {
	pattern = "rust",
	callback = function(args)
		on_attach(nil, args.buf)
	end,
})

vim.g.rustaceanvim = {
	tools = {
		-- Plugin configuration
		--TODO
		--test_executor = 'backround',
		Opts = {
			enable_clippy = false, --  Whether to enable clippy checks on save if a clippy installation is detected. Default: `true`. I want this to be conditional on a .g var that's toggled depending on which stage of dev process I'm in.
		}
	},
	dap = {
		adapter = codelldb_adapter(),
	},
	server = {
		logfile = "/home/v/.local/state/nvim/rustaceanvim.log", --XXX: not user-agnostic
		status_notify_level = rustaceanvim.disable,           -- doesn't work
		--on_attach = on_attach, //BUG: doesn't work
		--XXX: does nothing. Atm can't get it to use anything but default "utf-8"
		--capabilities = (function()
		--	local caps = require('rustaceanvim.config.server').create_client_capabilities()
		--	caps.general.positionEncodings = capabilities.general.positionEncodings
		--	return caps
		--end)(),
		default_settings = {
			['rust-analyzer'] = (function()
				local settings = {
					dap = {
						autoload_configuration = true,
					},
					cmd = {
						"rust-analyzer",
					},
					cargo = {
						BuildScripts = {
							enable = true,
						},
						runBuildScripts = true,
						loadOutDirsFromCheck = true,
						--allFeatures = true, -- will break on projects with incompatible features. If comes up, write a script to copy code before uploading to crates.io and sed `features = ["full"]` for `[]`
					},
					procMacro = {
						enable = true,
					},
					completion = {
						excludeTraits = {
							"owo_colors::FgColorDisplay",
							"owo_colors::BgColorDisplay",
						},
					},
					checkOnSave = {
						enable = true,
						--command = function() return vim.g.rust_check_with end, --doesn't work
						command = vim.g
								.rust_check_with --HACK: can't figure out how to make interactive. This is sourced only at the server init. So have to restart for this to apply.
					},
				}
				local cargo_exists = vim.fn.filereadable(vim.fn.getcwd() .. "/Cargo.toml") == 1
				if cargo_exists then
					-- RA is being dumb, so on cargo-script projects touching workspaces leads to very annoying warnings
					settings.workspace = {
						symbol = {
							search = {
								-- default is "only_types"
								kind = "all_symbols",
							},
						},
					}
				end
				return settings
			end)(),
		},
	},
}

-- Export for other modules
local M = {}

M.capabilities = capabilities
M.on_attach = on_attach

M.get_preferred_encoding = function()
	return capabilities.general.positionEncodings[1]
end

return M
