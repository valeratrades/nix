-- Terminal file chooser for xdg-desktop-portal-termfilechooser
-- Usage: nvim +TermFileChooserOpen:/path/to/tmpfile /start/dir
--        nvim +TermFileChooserSave:/path/to/statusfile /path/to/tmpfile

local M = {}

_G.filechooser_marks = {}
_G.filechooser_ns = vim.api.nvim_create_namespace('filechooser')

function M.setup_open(tmpfile)
  -- When a regular file is opened, capture path and exit immediately
  -- Use BufReadCmd to completely intercept the file load
  vim.api.nvim_create_autocmd('BufReadCmd', {
    callback = function()
      local file = vim.fn.expand('<afile>:p')
      -- Skip oil:// buffers
      if file:match('^oil://') then return end
      if vim.fn.filereadable(file) == 1 then
        local f = io.open(tmpfile, 'w')
        if f then
          f:write(file)
          f:close()
        end
        vim.cmd('qa!')
      end
    end
  })

  -- Oil.nvim keybindings
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'oil',
    callback = function(ev)
      local oil = require('oil')

      -- 's' to mark/unmark files
      vim.keymap.set('n', 's', function()
        local entry = oil.get_cursor_entry()
        if entry and entry.type == 'file' then
          local path = oil.get_current_dir() .. entry.name
          local lnum = vim.fn.line('.')
          if _G.filechooser_marks[path] then
            _G.filechooser_marks[path] = nil
            vim.api.nvim_buf_clear_namespace(ev.buf, _G.filechooser_ns, lnum - 1, lnum)
          else
            _G.filechooser_marks[path] = true
            vim.api.nvim_buf_set_extmark(ev.buf, _G.filechooser_ns, lnum - 1, 0, {
              sign_text = '*',
              sign_hl_group = 'DiagnosticSignWarn'
            })
          end
        end
      end, { buffer = true })

      -- Tab to confirm marked files
      vim.keymap.set('n', '<Tab>', function()
        local paths = {}
        for p in pairs(_G.filechooser_marks) do
          table.insert(paths, p)
        end
        if #paths > 0 then
          local f = io.open(tmpfile, 'w')
          if f then
            for i, p in ipairs(paths) do
              f:write(p)
              if i < #paths then f:write('\n') end
            end
            f:close()
          end
          vim.cmd('qa!')
        end
      end, { buffer = true })

      -- Visual Tab to select range
      vim.keymap.set('v', '<Tab>', function()
        local dir = oil.get_current_dir()
        local start_line = vim.fn.line('v')
        local end_line = vim.fn.line('.')
        if start_line > end_line then
          start_line, end_line = end_line, start_line
        end
        local paths = {}
        for lnum = start_line, end_line do
          local entry = oil.get_entry_on_line(0, lnum)
          if entry and entry.type == 'file' then
            table.insert(paths, dir .. entry.name)
          end
        end
        if #paths > 0 then
          local f = io.open(tmpfile, 'w')
          if f then
            for i, p in ipairs(paths) do
              f:write(p)
              if i < #paths then f:write('\n') end
            end
            f:close()
          end
          vim.cmd('qa!')
        end
      end, { buffer = true })

      -- S to jump to Screenshots
      vim.keymap.set('n', 'S', function()
        oil.open(vim.fn.expand('~/tmp/Screenshots/'))
      end, { buffer = true })

      -- Abort keys
      for _, key in ipairs({ 'q', '<C-c>', '<A-;>', '<Esc>' }) do
        vim.keymap.set('n', key, function() vim.cmd('cq') end, { buffer = true })
      end
    end
  })
end

function M.setup_save(statusfile)
  -- Disable filetype detection for this buffer (it's just a path string)
  vim.cmd('setlocal filetype=')
  vim.cmd('setlocal buftype=')

  -- Store the tmpfile path (the file we're editing)
  local tmpfile = vim.fn.expand('%:p')

  -- Enter to confirm
  vim.keymap.set('n', '<CR>', function()
    -- Get the edited path from buffer and write directly to tmpfile
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local path = table.concat(lines, '\n')
    vim.fn.writefile({ path }, tmpfile)
    vim.fn.writefile({ '1' }, statusfile)
    vim.cmd('q!')
  end, { buffer = true })

  -- Abort keys
  for _, key in ipairs({ 'q', '<C-c>', '<A-;>', '<Esc>' }) do
    vim.keymap.set('n', key, function() vim.cmd('q!') end, { buffer = true })
  end
end

-- Register commands
vim.api.nvim_create_user_command('TermFileChooserOpen', function(opts)
  M.setup_open(opts.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command('TermFileChooserSave', function(opts)
  M.setup_save(opts.args)
end, { nargs = 1 })

return M
