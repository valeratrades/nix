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
	{ import = "valera.plugins.undotree" },
	'L3MON4D3/LuaSnip',
	"lewis6991/gitsigns.nvim",
	{ import = "valera.plugins.blankline" },
	{ import = "valera.plugins.copilot" },
	--"github/copilot.vim",
	{ import = "valera.plugins.treesitter" },
	{ import = "valera.plugins.telescope" },
	{ import = "valera.plugins.lualine" },
	{
		"numToStr/Comment.nvim",
		dependencies = {
			"JoosepAlviste/nvim-ts-context-commentstring",
		},
	},
	{ import = "valera.plugins.signature" },
	{ import = "valera.plugins.oil" },
	{ import = "valera.plugins.webdevicons" },
	{ -- Jake
		{ import = "valera.plugins.recursive-macro" },
		{ import = "valera.plugins.normon" },
		{ import = "valera.plugins.shnip" },
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
	{ import = "valera.plugins.cmp" },
	{ import = "valera.plugins.dap" },
	{ -- Lsp
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
		{ import = "valera.plugins.crates" },
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
		{ 'rose-pine/neovim',              name = 'rose-pine' },
		{ "catppuccin/nvim",               name = "catppuccin" },
		{ "folke/tokyonight.nvim",         name = "tokyonight" },
		{ "jdsimcoe/panic.vim",            name = "panic" }, -- perfect colors, bad mapping of color to element
		{ import = "valera.plugins.colors" },
	},
	{ -- Git
		'tpope/vim-fugitive',
		{ import = "valera.plugins.git" },
	},
	{ import = "valera.plugins.neotest" },
	--

	-- If something breaks, it's likely below here:

	--{ 'akinsho/toggleterm.nvim', version = "*", config = true }, // deprecated. Nvim seems to already have all the things I want. Delete this fallback reminder in a month.

	'vim-test/vim-test',
	'lervag/vimtex',
	{ import = "valera.plugins.sessions" },
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
	{ import = "valera.plugins.presence" },
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
	{ import = "valera.plugins.surround" },
	"valeratrades/typst.vim",
	{ import = "valera.plugins.leetcode" },
	"nanotee/zoxide.vim",
	{ import = "valera.plugins.color-picker" },
	{ import = "valera.plugins.log-highlight" },
	{ import = "valera.plugins.peek" },
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
	{ import = "valera.plugins.guess-indent" },
	{ 'wakatime/vim-wakatime',               lazy = false },
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
