local cfg = {
	debug = false, -- set to true to enable logging
	verbose = true,
	log_path = vim.fn.stdpath("cache") .. "/lsp_signature.log",

	wrap = false,
	floating_window = false,
	hint_enable = true,
	hint_prefix = "🐼 ",
	hint_scheme = "String",
	hi_parameter = "LspSignatureActiveParameter",
	always_trigger = false,
	auto_close_after = 3,
}

require 'lsp_signature'.setup(cfg)
