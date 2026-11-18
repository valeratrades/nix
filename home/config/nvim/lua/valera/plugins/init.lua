-- specs without a file of their own; every file in this dir is a spec module too (lazier lsmods it)
return {
	-- Cornerstone
	{ -- swaps siblings in any ts language; textobjects' swap only covers langs whose queries define `@parameter`
		"Wansmer/sibling-swap.nvim",
		opts = { use_default_keymaps = false },
		keys = {
			{ "g<", function() require('sibling-swap').swap_with_left() end,  desc = "Swap with left sibling" },
			{ "g>", function() require('sibling-swap').swap_with_right() end, desc = "Swap with right sibling" },
		},
	},
	"numToStr/Comment.nvim",
	{
		"JoosepAlviste/nvim-ts-context-commentstring",
		opts = { enable_autocmd = false },
	},
	{ -- https://github.com/tpope/vim-abolish/blob/master/doc/abolish.txt
		'tpope/vim-abolish',
		keys = {
			{ "<Space>cr" },
		},
		-- ex: :%S/facilit{y,ies}/building{,s}/g
		cmd = { "S", "Subvert" },
	},
	-- similar to helix's match
	"wellle/targets.vim",
	{ -- Lsp
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v4.x',
		dependencies = {
			-- LSP Support
			'neovim/nvim-lspconfig',          -- Cornerstone. lsp-zero is built on top of it.
			'williamboman/mason.nvim',        -- lsp-servers file-manager
			'williamboman/mason-lspconfig.nvim', -- lsp-servers file-manager
			'lukas-reineke/lsp-format.nvim',  -- Auto-Formatting
			'onsails/lspkind.nvim',
		}
	},
	{ 'mrcjkb/rustaceanvim', ft = 'rust' },
	{                            -- Math
		dir = '/home/v/g/lean.nvim', --TODO: switch to 'Julian/lean.nvim', once [my pr](https://github.com/Julian/lean.nvim/pull/485) is accepted
		event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
		dependencies = {
			'neovim/nvim-lspconfig',
			'nvim-lua/plenary.nvim',
		},
		build = false,
	},
	{ 'rose-pine/neovim',            name = 'rose-pine' },
	{ -- lazier caches the colorscheme set while its spec compiles and paints it before the first frame
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = false,
		priority = 1000,
		config = function() vim.cmd.colorscheme("catppuccin-mocha") end,
	},
	{ "folke/tokyonight.nvim",       name = "tokyonight" },
	{ "jdsimcoe/panic.vim",          name = "panic" },   -- perfect colors, bad mapping of color to element
	{ "projekt0n/github-nvim-theme", lazy = true },      -- light mode; lazy's colorscheme handler loads it on `:colorscheme github_*`
	'tpope/vim-fugitive',
	--

	-- If something breaks, it's likely below here:

	--{ 'akinsho/toggleterm.nvim', version = "*", config = true }, // deprecated. Nvim seems to already have all the things I want. Delete this fallback reminder in a month.

	'vim-test/vim-test',
	'lervag/vimtex',
	'nvim-telescope/telescope-file-browser.nvim',
	'nvim-telescope/telescope-media-files.nvim',
	{
		"nvim-telescope/telescope-ui-select.nvim",
		dependencies = { "echasnovski/mini.icons" },
	},
	"nvim-lua/popup.nvim",
	"folke/persistence.nvim",
	"folke/todo-comments.nvim",
	'jbyuki/instant.nvim',
	"valeratrades/typst.vim",
	"nanotee/zoxide.vim",
	--{
	--	"iamcco/markdown-preview.nvim",
	--	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	--	ft = { "markdown" },
	--	build = function() vim.fn["mkdp#util#install"]() end,
	--},

	"echasnovski/mini.ai",

	"nvim-neotest/nvim-nio",
	'arnamak/stay-centered.nvim',
	"DreamMaoMao/yazi.nvim",
	"norcalli/nvim-colorizer.lua",
	{
		"valeratrades/rainbow-delimiters.nvim", -- fork until HiPhish/rainbow-delimiters.nvim#223 (nil-parser guard) lands
		branch = "guard-nil-parser-on-reattach",
		config = function()
			-- Register a typst query without math $ (we color those separately)
			vim.treesitter.query.set('typst', 'rainbow-delimiters-nomathdollar', [[
				(group "(" @delimiter ")" @delimiter @sentinel) @container
				(block "{" @delimiter "}" @delimiter @sentinel) @container
				(content "[" @delimiter "]" @delimiter @sentinel) @container
				(call "(" @delimiter ")" @delimiter @sentinel) @container
			]])
			vim.g.rainbow_delimiters = {
				query = {
					typst = 'rainbow-delimiters-nomathdollar',
				},
			}
		end,
	},
	"Makaze/AnsiEsc",
	"stevearc/aerial.nvim",
	--{ "tjdevries/ocaml.nvim",  build = "make" }, -- requires 3.17 dune, but my nix only has 3.16
	"folke/which-key.nvim",
	--"pimalaya/himalaya-vim", --TODO: setup
	"jecaro/fugitive-difftool.nvim",
	--"Saghen/blink.cmp", -- potentially a better nvim-cmp, worth trying at some point
}
