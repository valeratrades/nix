local chafa_ns = vim.api.nvim_create_namespace("markdown_chafa")
local active_mode = nil -- "uberzug" | "chafa" | nil

--- Resolve image path, converting .excalidraw to .svg if needed
local function resolve_image_path(document_path, image_url)
	local path
	if image_url:sub(1, 1) == "/" then
		path = image_url
	elseif image_url:sub(1, 1) == "~" then
		path = vim.fn.fnamemodify(image_url, ":p")
	else
		local dir = vim.fn.fnamemodify(document_path, ":h")
		path = vim.fn.fnamemodify(dir .. "/" .. image_url, ":p")
	end

	if path:match("%.excalidraw$") and vim.fn.filereadable(path) == 1 then
		local svg = "/tmp/markdown_svg_compile" .. path .. ".svg"
		local svg_dir = vim.fn.fnamemodify(svg, ":h")
		vim.fn.mkdir(svg_dir, "p")
		if vim.fn.filereadable(svg) == 0 or vim.fn.getftime(svg) < vim.fn.getftime(path) then
			vim.fn.system({ "excalidraw_export", path, svg })
		end
		return svg
	end

	return path
end

--- Extract size percent from image alt text, e.g. "test 80%" -> 80
local function parse_size_percent(alt_text)
	local pct = alt_text:match("(%d%d?%d?)%%$")
	if pct then return tonumber(pct) end
	return nil
end

--- Parse buffer for markdown image links using treesitter
local function query_buffer_images(buf)
	local parser = vim.treesitter.get_parser(buf, "markdown")
	parser:parse(true)
	local inlines = parser:children()["markdown_inline"]
	if not inlines then return {} end

	local inline_query = vim.treesitter.query.parse("markdown_inline",
		"(image (image_description) @alt (link_destination) @url) @image")
	local images = {}

	inlines:for_each_tree(function(tree)
		local root = tree:root()
		local current = nil
		---@diagnostic disable-next-line: missing-parameter
		for id, node in inline_query:iter_captures(root, buf) do
			local key = inline_query.captures[id]
			if key == "image" then
				local sr, sc, er, ec = node:range()
				current = { range = { start_row = sr, start_col = sc, end_row = er, end_col = ec } }
			elseif current and key == "alt" then
				current.size_pct = parse_size_percent(vim.treesitter.get_node_text(node, buf))
			elseif current and key == "url" then
				current.url = vim.treesitter.get_node_text(node, buf)
				table.insert(images, current)
				current = nil
			end
		end
	end)

	return images
end

local function chafa_clear(buf)
	vim.api.nvim_buf_clear_namespace(buf or 0, chafa_ns, 0, -1)
end

local function chafa_render(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	chafa_clear(buf)

	local file_path = vim.api.nvim_buf_get_name(buf)
	local images = query_buffer_images(buf)
	local win_width = vim.api.nvim_win_get_width(0)

	for _, img in ipairs(images) do
		local path = resolve_image_path(file_path, img.url)
		if vim.fn.filereadable(path) == 1 then
			local w = img.size_pct and math.floor(win_width * img.size_pct / 100) or win_width
			local output = vim.fn.system({ "chafa", "-f", "symbols", "--colors", "none", "--size", w .. "x25", path })
			if vim.v.shell_error == 0 then
				local lines = {}
				for line in output:gmatch("[^\n]+") do
					table.insert(lines, { { line, "" } })
				end
				if #lines > 0 then
					vim.api.nvim_buf_set_extmark(buf, chafa_ns, img.range.start_row, 0, {
						virt_lines = lines,
						virt_lines_above = false,
					})
				end
			end
		end
	end
end

local function clear_active()
	if active_mode == "image.nvim" then
		pcall(function() require("image").disable() end)
	elseif active_mode == "chafa" then
		chafa_clear()
	end
end

local function enable_image_nvim()
	clear_active()
	require("lazy").load({ plugins = { "image.nvim" } })
	require("image").enable()
	vim.cmd("doautocmd BufWinEnter")
	active_mode = "image.nvim"
end

vim.api.nvim_create_user_command("MarkdownAuto", enable_image_nvim,
	{ desc = "Render markdown images (kitty if supported, uberzug otherwise)" })

vim.api.nvim_create_user_command("MarkdownUberzug", enable_image_nvim,
	{ desc = "Render markdown images via image.nvim" })

vim.api.nvim_create_user_command("MarkdownChafa", function()
	clear_active()
	chafa_render()
	active_mode = "chafa"
end, { desc = "Render markdown images as terminal art via chafa" })

vim.api.nvim_create_user_command("MarkdownNormal", function()
	clear_active()
	active_mode = nil
end, { desc = "Return to normal markdown editing" })

return {}
