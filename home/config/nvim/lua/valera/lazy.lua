local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)
vim.g.mapleader = ' ' -- ensure mappings are correct

-- dancing with a buben, to not have to move out the plugins from existing table
--TODO!!!: \
--local plugin_path = debug.getinfo(1, 'S').source:sub(2):match("(.*/)")
--local plugin_specs = {}
--for _, file in ipairs(vim.fn.glob(plugin_path .. "plugins/*.lua", true, true)) do
--	local spec = dofile(file)
--	if type(spec) == "table" then
--		table.insert(plugin_specs, spec)
--	end
--end


--return require('lazy').setup(vim.tbl_extend("force", {
return require('lazy').setup({
	-- Cornerstone
	--'theprimeagen/harpoon',
	'mbbill/undotree',
	'L3MON4D3/LuaSnip',
	"lewis6991/gitsigns.nvim",
	'lukas-reineke/indent-blankline.nvim',
	"zbirenbaum/copilot.lua",
	--"github/copilot.vim",
	{ -- Treesitter
		{ 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' },
		"nvim-treesitter/nvim-treesitter-textobjects",
		"nvim-treesitter/nvim-treesitter-context",
		"JoosepAlviste/nvim-ts-context-commentstring",
		"windwp/nvim-ts-autotag",
		"windwp/nvim-autopairs",
	},
	{
		'nvim-telescope/telescope.nvim',
		dependencies = {
			'nvim-lua/plenary.nvim',
			"nvim-telescope/telescope-live-grep-args.nvim",
			"nvim-telescope/telescope-fzf-native.nvim",
		},
		opts = {
			extensions_list = { "fzf", "terms", "themes" },
		},
	},
	{
		'nvim-lualine/lualine.nvim',
		dependencies = {
			{ 'nvim-tree/nvim-web-devicons', lazy = true },
			"lewis6991/gitsigns.nvim",
			"nvim-lua/lsp-status.nvim",
		}
	},
	{
		'numToStr/Comment.nvim',
		config = function()
			require('Comment').setup()
		end
	},
	{
		"ray-x/lsp_signature.nvim",
		event = "VeryLazy",
	},
	{
		'stevearc/oil.nvim',
		dependencies = { "nvim-tree/nvim-web-devicons" },
	},
	{ -- Jake
		-- 2q and then Q for recursive macro
		'jake-stewart/recursive-macro.nvim',
		-- helix for poor people
		'jake-stewart/normon.nvim',
		'jake-stewart/shnip.nvim',
	},
	{ -- https://github.com/tpope/vim-abolish/blob/master/doc/abolish.txt
		'tpope/vim-abolish',
		keys = {
			{ "<Space>cr" },
		},
		-- ex: :%S/facilit{y,ies}/building{,s}/g
		cmd = { "S", "Subvert" },
	},
	{ -- CamelCaseACRONYMWords_underscore1234
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
	},
	-- similar to helix's match
	"wellle/targets.vim",
	{ -- Cmp
		'hrsh7th/nvim-cmp',
		'hrsh7th/cmp-nvim-lsp',
		'hrsh7th/cmp-buffer',
		'hrsh7th/cmp-path',
		'hrsh7th/cmp-cmdline',
		'saadparwaiz1/cmp_luasnip',
		'hrsh7th/cmp-nvim-lua',
	},
	{ -- Dap
		'mfussenegger/nvim-dap',
		'leoluz/nvim-dap-go',
		'mfussenegger/nvim-dap-python',
		{ 'rcarriga/nvim-dap-ui', name = 'dapui' },
		'nvim-neotest/nvim-nio',
		'theHamsta/nvim-dap-virtual-text',
		'nvim-telescope/telescope-dap.nvim',
		'jay-babu/mason-nvim-dap.nvim', -- don't use it because nix, but still must be here as a dep, because lua
	},
	{                               -- Lsp
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',
		dependencies = {
			-- LSP Support
			'neovim/nvim-lspconfig',          -- Cornerstone. lsp-zero is built on top of it.
			'williamboman/mason.nvim',        -- lsp-servers file-manager
			'williamboman/mason-lspconfig.nvim', -- lsp-servers file-manager
			'lukas-reineke/lsp-format.nvim',  -- Auto-Formatting
			'onsails/lspkind.nvim',
		}
	},
	{ -- Rust
		'Saecki/crates.nvim',
	},
	{ -- Math
		'Julian/lean.nvim',
		event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
		dependencies = {
			'neovim/nvim-lspconfig',
			'nvim-lua/plenary.nvim',
		},
	},
	{ -- Colorschemes
		{ 'rose-pine/neovim',      name = 'rose-pine' },
		{ "catppuccin/nvim",       name = "catppuccin" },
		{ "folke/tokyonight.nvim", name = "tokyonight" },
		{ "jdsimcoe/panic.vim",    name = "panic" }, -- perfect colors, bad mapping of color to element
		"projekt0n/github-nvim-theme",
	},
	{ -- Git
		'tpope/vim-fugitive',
	},
	{ -- Testing
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-neotest/nvim-nio",
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-treesitter/nvim-treesitter"
		},
	},
	--

	-- If something breaks, it's likely below here:

	--{ 'akinsho/toggleterm.nvim', version = "*", config = true }, // deprecated. Nvim seems to already have all the things I want. Delete this fallback reminder in a month.
	{
		'mrcjkb/rustaceanvim',
		lazy = false, -- This plugin is already lazy
	},

	'vim-test/vim-test',
	'lervag/vimtex',
	'olimorris/persisted.nvim',
	'nvim-telescope/telescope-file-browser.nvim',
	'nvim-telescope/telescope-media-files.nvim',
	{
		"nvim-telescope/telescope-ui-select.nvim",
		deps = { "echasnovski/mini.icons" },
	},
	"nvim-lua/popup.nvim",
	"folke/persistence.nvim",
	"folke/todo-comments.nvim",
	'jbyuki/instant.nvim',
	"andweeb/presence.nvim",
	{
		'cameron-wags/rainbow_csv.nvim',
		config = true,
		ft = {
			'csv',
			'tsv',
			'csv_semicolon',
			'csv_whitespace',
			'csv_pipe',
			'rfc_csv',
			'rfc_semicolon'
		},
		cmd = {
			'RainbowDelim',
			'RainbowDelimSimple',
			'RainbowDelimQuoted',
			'RainbowMultiDelim'
		}
	},
	{
		"kdheepak/lazygit.nvim",
		cmd = {
			"LazyGit",
			"LazyGitConfig",
			"LazyGitCurrentFile",
			"LazyGitFilter",
			"LazyGitFilterCurrentFile",
		},
		-- optional for floating window border decoration
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
	},
	{
		"kylechui/nvim-surround",
		version = "*",
		event = "VeryLazy",
	},
	{
		'kaarmu/typst.vim',
		config = function()
			vim.g.typst_embedded_languages = { 'rs -> rust', 'md -> markdown', 'py -> python' }
		end,
	},
	{
		'kawre/leetcode.nvim',
		build = ":TSUpdate html",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-telescope/telescope.nvim",
			"nvim-lua/plenary.nvim", -- required by telescope
			"MunifTanjim/nui.nvim",

			-- optional
			"rcarriga/nvim-notify",
			"nvim-tree/nvim-web-devicons",
		},
	},
	"nanotee/zoxide.vim",
	{
		"ziontee113/color-picker.nvim",
		config = function()
			require("color-picker").setup()
		end

	},
	{
		'fei6409/log-highlight.nvim',
		config = function()
			require('log-highlight').setup {
				extension = { "log", "window" },
			}
		end,
	},
	{
		"toppair/peek.nvim",
		event = { "VeryLazy" },
		build = "deno task --quiet build:fast",
	},
	--{
	--	"iamcco/markdown-preview.nvim",
	--	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	--	ft = { "markdown" },
	--	build = function() vim.fn["mkdp#util#install"]() end,
	--},

	{
		'gabrielpoca/replacer.nvim',
		opts = { rename_files = false },
		keys = {
			{
				'<space>h',
				function() require('replacer').run() end,
				desc = "run replacer.nvim"
			}
		}
	},
	{
		"folke/trouble.nvim",
		opts = {
			modes = {
				symbols = {
					--auto_open = true, -- behaves inconsistently, have to do manually
					--auto_close = true, -- without `auto_open`, just nukes itself when navigating
					auto_refresh = true,
					warn_no_results = false,
					pinned = false, -- don't pin to initial window (doesn't work)
					focus = false, -- don't focus on open
				},
			},
		},
		cmd = "Trouble",
		keys = {
			{
				"<space><space>x",
				"<cmd>Trouble symbols close<cr><cmd>Trouble symbols open<cr>", --HACK: with current impl it's pinned to the window. So if I need it in another one - must first close. (2025/06/06)
				desc = "Symbols (Trouble)",
			},
		},
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		---@type Flash.Config
		opts = {
			modes = {
				char = {
					enabled = false,
				},
			},
			labels = 'abcdefghijklmnopqrstuvwxyz',
		},
		jump = {
			pos = 'range', ---@type "start" | "end" | "range"
			autojump = true, -- automatically jump when there is only one match
		},
		-- tylua: ignore
		keys = {
			{ "<space>x", mode = { "n", "x", "o" }, function() require("flash").jump() end,       desc = "Flash" },
			{ "<space>X", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
		},
	},
	-- Reasonable only with `kitty`. And then still worse than vscode, I think it's better to diagnostics pane and call it a day.
	--{
	--	"Isrothy/neominimap.nvim",
	--	version = "v3.x.x",
	--	lazy = false, -- NOTE: NO NEED to Lazy load
	--	-- Optional. You can alse set your own keybindings
	--	keys = {
	--		-- Global Minimap Controls
	--		{ "<leader>nm",  "<cmd>Neominimap toggle<cr>",      desc = "Toggle global minimap" },
	--		{ "<leader>no",  "<cmd>Neominimap on<cr>",          desc = "Enable global minimap" },
	--		{ "<leader>nc",  "<cmd>Neominimap off<cr>",         desc = "Disable global minimap" },
	--		{ "<leader>nr",  "<cmd>Neominimap refresh<cr>",     desc = "Refresh global minimap" },
	--
	--		-- Window-Specific Minimap Controls
	--		{ "<leader>nwt", "<cmd>Neominimap winToggle<cr>",   desc = "Toggle minimap for current window" },
	--		{ "<leader>nwr", "<cmd>Neominimap winRefresh<cr>",  desc = "Refresh minimap for current window" },
	--		{ "<leader>nwo", "<cmd>Neominimap winOn<cr>",       desc = "Enable minimap for current window" },
	--		{ "<leader>nwc", "<cmd>Neominimap winOff<cr>",      desc = "Disable minimap for current window" },
	--
	--		-- Tab-Specific Minimap Controls
	--		{ "<leader>ntt", "<cmd>Neominimap tabToggle<cr>",   desc = "Toggle minimap for current tab" },
	--		{ "<leader>ntr", "<cmd>Neominimap tabRefresh<cr>",  desc = "Refresh minimap for current tab" },
	--		{ "<leader>nto", "<cmd>Neominimap tabOn<cr>",       desc = "Enable minimap for current tab" },
	--		{ "<leader>ntc", "<cmd>Neominimap tabOff<cr>",      desc = "Disable minimap for current tab" },
	--
	--		-- Buffer-Specific Minimap Controls
	--		{ "<leader>nbt", "<cmd>Neominimap bufToggle<cr>",   desc = "Toggle minimap for current buffer" },
	--		{ "<leader>nbr", "<cmd>Neominimap bufRefresh<cr>",  desc = "Refresh minimap for current buffer" },
	--		{ "<leader>nbo", "<cmd>Neominimap bufOn<cr>",       desc = "Enable minimap for current buffer" },
	--		{ "<leader>nbc", "<cmd>Neominimap bufOff<cr>",      desc = "Disable minimap for current buffer" },
	--
	--		---Focus Controls
	--		{ "<leader>nf",  "<cmd>Neominimap focus<cr>",       desc = "Focus on minimap" },
	--		{ "<leader>nu",  "<cmd>Neominimap unfocus<cr>",     desc = "Unfocus minimap" },
	--		{ "<leader>ns",  "<cmd>Neominimap toggleFocus<cr>", desc = "Switch focus on minimap" },
	--	},
	--	init = function()
	--		-- The following options are recommended when layout == "float"
	--		vim.opt.wrap = false
	--		vim.opt.sidescrolloff = 36 -- Set a large value
	--
	--		--- Put your configuration here
	--		---@type Neominimap.UserConfig
	--		vim.g.neominimap = {
	--			auto_enable = false,
	--		}
	--	end,
	--},

	"echasnovski/mini.ai",

	"nvim-neotest/nvim-nio",
	'arnamak/stay-centered.nvim',
	--"3rd/image.nvim", -- want's luarocks, which I haven't yet set up with nix
	"DreamMaoMao/yazi.nvim",
	"norcalli/nvim-colorizer.lua",
	--"hiphish/rainbow-delimiters.nvim", -- alternate bracket colors
	"Makaze/AnsiEsc",
	"tpope/vim-speeddating",
	"stevearc/aerial.nvim",
	"https://codeberg.org/FelipeLema/cmp-async-path",
	"NMAC427/guess-indent.nvim",
	{ 'wakatime/vim-wakatime', lazy = false },
	--{ "tjdevries/ocaml.nvim",  build = "make" }, -- requires 3.17 dune, but my nix only has 3.16
	"folke/which-key.nvim",
	--"pimalaya/himalaya-vim", --TODO: setup
	{
		"gabrielpoca/replacer.nvim",
		keys = {
			{
				'<Space>h',
				function() require('replacer').run() end,
				desc = "run replacer.nvim"
			}
		}
	},
	"jecaro/fugitive-difftool.nvim",
	--"Saghen/blink.cmp", -- potentially a better nvim-cmp, worth trying at some point
	{
		"https://github.com/amitds1997/remote-nvim.nvim",
		version = "*",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-telescope/telescope.nvim",
		},
		config = function()
			require("remote-nvim").setup({
				client_callback = function(port, workspace_config)
					local session_name = "remote-" .. workspace_config.host
					local cmd = string.format(
						"tmux new-session -d -s %s 'nvim --server localhost:%s --remote-ui'",
						session_name,
						port
					)
					vim.fn.jobstart(cmd, {
						detach = true,
						on_exit = function(job_id, exit_code, event_type)
							print(string.format("Client %d exited with code %d (Event: %s)", job_id, exit_code, event_type))
						end,
					})
				end,
				offline_mode = {
					enabled = false, --TEST
					no_github = true, -- whether not to even try to fetch from github
				},
			})
		end,
	},
})
--}, plugin_specs))
