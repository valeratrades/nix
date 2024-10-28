local cmp = require('cmp')
local _ = { behavior = cmp.SelectBehavior.Select } -- makes cmp not force feed me completeions on 'Enter'
local cmp_action = require('lsp-zero').cmp_action()
local ts_utils = require('nvim-treesitter.ts_utils')
local lspkind = require('lspkind')

-- modes: `i`nsert, `s`elect, `c`ommand
local mappings = {
	['<C-s>'] = cmp_action.luasnip_supertab(),
	['<C-y>'] = cmp.mapping.confirm({ select = true }),

	-- impossible to overwrite the defaults. There is literally no way to make this work, - without cmp.mapping.preset.insert this is not registered at all.
	--['<C-r>'] = cmp.mapping(cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }), { 'i', 's', 'c' }),
	--['<C-n>'] = cmp.mapping(cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }), { 'i', 's', 'c' }),

	['<Right>'] = cmp.mapping(cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }), { 'c' }),
	['<Left>'] = cmp.mapping(cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }), { 'c' }),

	['<C-d>'] = cmp.mapping(function()
		if cmp.visible() then
			cmp.scroll_docs(4)
		end
	end, {
		"i",
		"s",
	}),
	['<C-u>'] = cmp.mapping(function()
		if cmp.visible() then
			cmp.scroll_docs(-4)
		end
	end, {
		"i",
		"s",
	}),
	['<C-c>'] = cmp.mapping(cmp.mapping.complete_common_string(), { "i", "s", "c" }),
}


-- max_item_count doesn't seem to work
vim.opt.completeopt = { "menu", "menuone", "noselect" }
cmp.setup({
	sources = cmp.config.sources({
		{
			name = 'nvim_lsp',
			keyword_lenght = 1,
			max_item_count = 12,
			-- when inputting an argument, suggest only values with this in mind
			entry_filter = function(entry, _context)
				local success = pcall(function()
					local node = ts_utils.get_node_at_cursor():type()
					if node == "arguments" then
						local kind = entry:get_kind()
						return kind == 6
					end
				end)
				return success or true
			end,
		},
		{ name = 'luasnip',   keyword_length = 1, max_item_count = 8 },
		{ name = 'buffer',    keyword_length = 5, max_item_count = 8 },
		--{ name = 'cmdline',   keyword_length = 3, max_item_count = 8 }, // does nothing here (why, nvim-cmp, whyy)
		{ name = "crates" },
		{ name = "async_path" },
	}),
	formatting = {
		fields = { 'abbr', 'kind', 'menu' },
		format = lspkind.cmp_format({
			mode = 'symbol',
			preset = 'codicons', -- can be either 'default' (requires nerd-fonts font) or 'codicons' for codicon preset (requires vscode-codicons font)
			maxwidth = 50,
			ellipsis_char = '..', -- when exceeds maxwidth

			symbol_map = {
				Text = "",
				Module = "",
				File = "",
				Folder = "",
				Operator = "",
				Color = "",
				Snippet = "",
				Value = "",
				Constructor = "",
				Event = "",
				Constant = "'static",
				Unit = "{}",
				Method = "𝗠",
				Function = "𝗙",
				Field = "𝗳",
				Variable = "𝘃",
				Class = "𝗖",
				Enum = "𝗘",
				Keyword = "𝘄",
				Reference = "𝗿",
				EnumMember = "𝗲",
				Struct = "𝗦",
				TypeParameter = "𝗧",
				Property = "𝗽",
				Interface = "𝗶",
			},

			-- executes before the rest, to add on popup customization. (See [#30](https://github.com/onsails/lspkind-nvim/pull/30))
			before = function(entry, item)
				local n = entry.source.name
				if n == 'nvim_lsp' then
					item.menu = 'LSP'
				elseif n == 'nvim_lua' then
					item.menu = 'nvim'
				elseif n == 'cmdline' then
					item.menu = ''
				elseif n == 'buffer' then
					item.menu = 'B'
				else
					--item.menu = string.format('[%s]', n)
					item.menu = n
				end
				return item
			end
		})
	},
	snippet = {
		expand = function(args)
			require('luasnip').lsp_expand(args.body)
		end,
	},
	window = {
		completion = cmp.config.window.bordered(),
		documentation = cmp.config.window.bordered(),
	},
	--mapping = cmp.mapping.preset.insert(mappings),
	mapping = mappings,
})
cmp.setup.cmdline({ '/', '?' }, {
	mapping = cmp.mapping.preset.cmdline(),
	sources = {
		{ name = 'buffer' }
	}
})
cmp.setup.cmdline(':', {
	--mapping = cmp.mapping.preset.cmdline(),
	sources = cmp.config.sources({
		{ name = 'path' }
	}, {
		{
			name = 'cmdline',
			option = {
				ignore_cmds = { 'Man', '!' }
			},
			max_item_count = 15,
		},
	})
})
