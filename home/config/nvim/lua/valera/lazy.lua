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

--return require('lazy').setup(vim.tbl_extend("force", {
return require('lazy').setup({
	-- Cornerstone
	--'theprimeagen/harpoon',
	'mbbill/undotree',
	'L3MON4D3/LuaSnip',
	"lewis6991/gitsigns.nvim",
	'lukas-reineke/indent-blankline.nvim',
	{ import = "valera.plugins.copilot" },
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
	{ import = "valera.plugins.wordmotion" },
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
		{ 'mfussenegger/nvim-dap-python', build = false },
		{ 'rcarriga/nvim-dap-ui',         name = 'dapui' },
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
		{ import = "valera.plugins.rustaceanvim" },
	},
	{ -- Math
		'Julian/lean.nvim',
		event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
		dependencies = {
			'neovim/nvim-lspconfig',
			'nvim-lua/plenary.nvim',
		},
		build = false,
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
	{ import = "valera.plugins.rainbow_csv" },
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
	{ import = "valera.plugins.typst" },
	{ import = "valera.plugins.leetcode" },
	"nanotee/zoxide.vim",
	{ import = "valera.plugins.color-picker" },
	{ import = "valera.plugins.log-highlight" },
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

	{ import = "valera.plugins.replacer" },
	{ import = "valera.plugins.trouble" },
	{ import = "valera.plugins.flash" },
	"echasnovski/mini.ai",

	"nvim-neotest/nvim-nio",
	'arnamak/stay-centered.nvim',
	--"3rd/image.nvim", -- want's luarocks, which I haven't yet set up with nix
	"DreamMaoMao/yazi.nvim",
	"norcalli/nvim-colorizer.lua",
	{ import = "valera.plugins.nvim-highlight-colors" },
	"hiphish/rainbow-delimiters.nvim", -- alternate bracket colors
	"Makaze/AnsiEsc",
	{ import = "valera.plugins.speeddating" },
	"stevearc/aerial.nvim",
	"https://codeberg.org/FelipeLema/cmp-async-path",
	"NMAC427/guess-indent.nvim",
	{ 'wakatime/vim-wakatime',              lazy = false },
	--{ "tjdevries/ocaml.nvim",  build = "make" }, -- requires 3.17 dune, but my nix only has 3.16
	"folke/which-key.nvim",
	--"pimalaya/himalaya-vim", --TODO: setup
	"jecaro/fugitive-difftool.nvim",
	--"Saghen/blink.cmp", -- potentially a better nvim-cmp, worth trying at some point
	{ import = "valera.plugins.remote-nvim" },
}, {
	-- atm prefer to just install them through systemPackages, natively to nix
	rocks = {
		enabled = false,
	},
})
--}, plugin_specs))
