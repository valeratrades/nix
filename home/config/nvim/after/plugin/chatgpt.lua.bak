require("chatgpt").setup({
	api_key_cmd = "echo OPENAI_KEY",
})

vim.keymap.set('n', '<Space>oc', '<cmd>ChatGPT<CR>', { desc = "ChatGPT: Open ChatGPT" })
local chatgpt_mappings = {
	{ '<Space>oa', '<cmd>ChatGPTRun add_tests<CR>',                 "ChatGPT: Add Tests" },
	{ '<Space>od', '<cmd>ChatGPTRun docstring<CR>',                 "ChatGPT: Docstring" },
	{ '<Space>oe', '<cmd>ChatGPTEditWithInstruction<CR>',           "ChatGPT: Edit with instruction" },
	{ '<Space>of', '<cmd>ChatGPTRun fix_bugs<CR>',                  "ChatGPT: Fix Bugs" },
	{ '<Space>og', '<cmd>ChatGPTRun grammar_correction<CR>',        "ChatGPT: Grammar Correction" },
	{ '<Space>ok', '<cmd>ChatGPTRun keywords<CR>',                  "ChatGPT: Keywords" },
	{ '<Space>ol', '<cmd>ChatGPTRun code_readability_analysis<CR>', "ChatGPT: Code Readability Analysis" },
	{ '<Space>oo', '<cmd>ChatGPTRun optimize_code<CR>',             "ChatGPT: Optimize Code" },
	{ '<Space>or', '<cmd>ChatGPTRun roxygen_edit<CR>',              "ChatGPT: Roxygen Edit" },
	{ '<Space>os', '<cmd>ChatGPTRun summarize<CR>',                 "ChatGPT: Summarize" },
	{ '<Space>ot', '<cmd>ChatGPTRun translate<CR>',                 "ChatGPT: Translate" },
	{ '<Space>ox', '<cmd>ChatGPTRun explain_code<CR>',              "ChatGPT: Explain Code" },
}
for _, mapping in ipairs(chatgpt_mappings) do
	vim.keymap.set({ 'n', 'v' }, mapping[1], mapping[2], { desc = mapping[3] })
end
