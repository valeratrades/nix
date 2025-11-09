return require "lazier" {
	"numToStr/Comment.nvim",
	dependencies = {
		"JoosepAlviste/nvim-ts-context-commentstring",
	},
	config = function()
		local util = require('ts_context_commentstring.utils')
		local config = {
			padding = false,
			sticky = true,
			ignore = nil,
			toggler = { line = 'gcc', block = 'gbc' },
			opleader = { line = 'gc', block = 'gb' },
			-- extra = { above = 'gcO', below = 'gco', eol = 'gcA' },
			mappings = { basic = true, extra = false }, -- reimplementing `extra` myself, to have padding on these and not on others
			pre_hook = function(ctx)
				if vim.bo.filetype == "typescript" then
					local location = nil
					if ctx.ctype == util.ctype.blockwise then
						location = require("ts_context_commentstring.utils").get_cursor_location()
					elseif ctx.cmotion == util.cmotion.v or ctx.cmotion == util.cmotion.V then
						location = require("ts_context_commentstring.utils").get_visual_start_location()
					end

					return require("ts_context_commentstring.internal").calculate_commentstring({
						key = ctx.ctype == util.ctype.linewise and "__default" or "__multiline",
						location = location,
					})
				end
			end,
			post_hook = nil,
		}
		require('Comment').setup(config)

		function CommentCopilotEsc()
			vim.b.copilot_enabled = false
		end

		--NB: this overwrites the default `extra` mappings from `Comment.nvim`; making this file necessary to be loaded in the old style, as doing it through `lazy.nvim`'s `config` field would source the default mappings second, overwriting these.
		K('n', 'gcO', function()
			require('rust_plugins').comment_extra_reimplementation('O')
		end, { desc = "comment: reimplement `gcO`" })
		K('n', 'gco', function()
			require('rust_plugins').comment_extra_reimplementation('o')
		end, { desc = "comment: reimplement `gco`" })
		K('n', 'gcA', function()
			require('rust_plugins').comment_extra_reimplementation('A ')
		end, { desc = "comment: reimplement `gcA`" })
		--

		-- -- Surround Block Comments
		function FoldmarkerCommentBlock(nesting_level)
			nesting_level = nesting_level or 1
			require('rust_plugins').foldmarker_comment_block(nesting_level)
		end

		for i = 1, 5 do
			K("v", "gb" .. i .. "f", string.format("<esc>`><cmd>lua FoldmarkerCommentBlock(%d)<cr>", i), {
				desc = string.format("Add a fold marker (nest %d) around selection", i),
			})
		end
		-- gbf as alias for gb1f
		K("v", "gbf", "<esc>`><cmd>lua FoldmarkerCommentBlock(1)<cr>", {
			desc = "Add a fold marker (nest 1) around selection",
		})
		--


		-- -- Draw a line thingie
		function DrawABigBeautifulLine(symbol)
			require('rust_plugins').draw_a_big_beautiful_line(symbol)
		end

		K('n', 'gc-i', "i<cmd>lua DrawABigBeautifulLine('-')<cr>", { desc = "comment: draw a '-' line here" })
		K('n', 'gc=i', "i<cmd>lua DrawABigBeautifulLine('=')<cr>", { desc = "comment: draw a '=' line here" })
		K('n', 'gc-o', "o<cmd>lua DrawABigBeautifulLine('-')<cr>", { desc = "comment: draw a '-' line below" })
		K('n', 'gc-O', "O<cmd>lua DrawABigBeautifulLine('-')<cr>", { desc = "comment: draw a '-' line above" })
		K('n', 'gc=o', "o<cmd>lua DrawABigBeautifulLine('=')<cr>", { desc = "comment: draw a '=' line below" })
		K('n', 'gc=O', "O<cmd>lua DrawABigBeautifulLine('=')<cr>", { desc = "comment: draw a '=' line above" })
		--


		-- -- Remove end of line comment
		local function removeEndOfLineComment()
			require('rust_plugins').remove_end_of_line_comment()
		end
		-- Note that if no `<space>{comment_string}` found on the current line, it will go searching through the rest of the file with `?`
		K('n', 'gcr', function() removeEndOfLineComment() end, { desc = "comment: remove end-of-line comment" })
		--

		-- -- `//dbg` Commments
		local function debugComment(action)
			return function()
				require('rust_plugins').debug_comment(action)
			end
		end
		K({ 'n', 'v' }, '<space>cda', debugComment('add'), { desc = "comment: add dbg comment", silent = true })
		K('n', '<space>cdr', debugComment('remove'), { desc = "comment: remove all debug lines", silent = true })
		--


		-- -- `TODO{!*n}` Comments
		function AddTodoComment(n)
			require('rust_plugins').add_todo_comment(n)
		end

		--K("n", "!", [[v:count == 0 ? '!' : ':lua AddTodoComment(' . v:count . ')<cr>']],
		K("n", "!", [[v:count == 0 ? ':lua AddTodoComment(3)<cr>' : ':lua AddTodoComment(' . v:count . ')<cr>']], -- default level
			--K("n", "!", [[':lua AddTodoComment(' . v:count . ')<cr>']],
			{ desc = "Add TODO comment", expr = true, silent = true, overwrite = true })
		K('n', '<space>1', '<cmd>lua AddTodoComment(0)<cr>', { desc = "Add TODO comment (no !)" })

		K('n', '<space>ch', function() require('rust_plugins').toggle_comments_visibility() end, { desc = "comment: toggle" })
	end,
}
