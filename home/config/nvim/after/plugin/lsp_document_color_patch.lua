-- nvim 0.12: `vim.lsp.document_color` is auto-enabled at module load
-- (`Capability.enable('document_color', true)` at bottom of document_color.lua).
-- Its `Provider:request` asserts `lsp.get_client_by_id(id)` is non-nil for every id
-- in `self.client_state`. If a client disappears without `on_detach` firing first
-- (e.g. server crash), the assert propagates out of `nvim_buf_attach`'s `on_lines`
-- callback as a user-visible "Press ENTER" error. Skip-and-cleanup is the right
-- behavior here: it's not data we computed wrong, it's just stale state.
do
	local Capability = require('vim.lsp._capability')
	require('vim.lsp.document_color') -- ensure registration
	local Provider = assert(Capability.all.document_color, "document_color registered on require")
	local lsp = vim.lsp
	local util = lsp.util

	function Provider:request(client_id)
		for id in pairs(self.client_state) do
			if not client_id or client_id == id then
				local client = lsp.get_client_by_id(id)
				if client then
					local params = { textDocument = util.make_text_document_params(self.bufnr) }
					client:request('textDocument/documentColor', params, function(...)
						self:handler(...)
					end, self.bufnr)
				else
					-- Stale entry: client gone without on_detach. Clean it up.
					self:on_detach(id)
				end
			end
		end
	end
end
