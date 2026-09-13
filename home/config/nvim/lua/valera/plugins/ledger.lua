-- hledger journals are ledger syntax. `ledger_align_at` is where `=` lands when
-- aligning a posting, which is what keeps a column of amounts readable.
return require "lazier" {
	"ledger/vim-ledger",
	ft = "ledger",
	init = function()
		vim.filetype.add({ extension = { journal = "ledger" } })
		vim.g.ledger_bin = "hledger"
		vim.g.ledger_align_at = 49
		vim.g.ledger_maxwidth = 80
		vim.g.ledger_default_commodity = "USD"
	end
}
