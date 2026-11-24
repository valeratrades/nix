-- Terminal file chooser for xdg-desktop-portal-termfilechooser
-- Usage: nvim +TermFileChooserOpen:/path/to/tmpfile /start/dir
--        nvim +TermFileChooserSave:/path/to/statusfile /path/to/tmpfile

local M = {}

local ABORT_KEYS = { 'q', '<C-c>', '<A-;>' }
local CONFIRM_KEYS = { '<CR>', '<M-a>' }
local SELECTABLE = { file = true, directory = true, link = true }

local marks = {}
local ns = vim.api.nvim_create_namespace('filechooser')

local function resolve_path(path)
  if vim.fn.isdirectory(path) == 1 then
    local name = path:match('([^/]+)/*$')
    local parent = path:match('^(.*)/[^/]+/*$') or '.'
    local zip = '/tmp/' .. name .. '.zip'
    local is_git = vim.fn.executable('git') == 1
      and vim.fn.system(string.format('git -C %s rev-parse --is-inside-work-tree 2>/dev/null', vim.fn.shellescape(path))):match('true')
    if is_git then
      -- NB: git archive only includes tracked files (respects .gitignore), but archives HEAD, not working tree
      vim.fn.system(string.format('git -C %s archive --format=zip --prefix=%s/ HEAD -o %s',
        vim.fn.shellescape(path), vim.fn.shellescape(name .. '/'), vim.fn.shellescape(zip)))
    else
      vim.fn.system(string.format('cd %s && zip -r %s %s',
        vim.fn.shellescape(parent), vim.fn.shellescape(zip), vim.fn.shellescape(name)))
    end
    return zip
  end
  return path
end

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

  -- drawn from `marks` on every redraw: oil rewrites its buffer on refresh and wipes hidden ones, taking extmarks along
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, buf) return vim.bo[buf].filetype == 'oil' end,
    on_line = function(_, _, buf, row)
      local oil = require('oil')
      local entry = oil.get_entry_on_line(buf, row + 1)
      if entry and marks[oil.get_current_dir(buf) .. entry.name] then
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
          end_row = row + 1,
          hl_group = 'CurSearch',
          hl_eol = true,
          priority = 10000, -- over oil's own column colors
          ephemeral = true,
        })
      end
    end,
  })

  -- Oil.nvim keybindings
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'oil',
    callback = function()
      local oil = require('oil')

      local function in_visual() return vim.fn.mode():match('[vV\22]') ~= nil end

      local function paths_in_range() -- outside visual mode line('v') is the cursor line
        local a, b = vim.fn.line('v'), vim.fn.line('.')
        local paths = {}
        for lnum = math.min(a, b), math.max(a, b) do
          local entry = oil.get_entry_on_line(0, lnum)
          if entry and SELECTABLE[entry.type] then
            table.insert(paths, oil.get_current_dir() .. entry.name)
          end
        end
        return paths
      end

      local function show_marks()
        if in_visual() then vim.cmd.normal({ '\27', bang = true }) end
        local names = vim.tbl_map(vim.fs.basename, vim.tbl_keys(marks))
        table.sort(names)
        vim.go.winbar = #names == 0 and ''
          or ('%%#CurSearch# %d marked: %s'):format(#names, table.concat(names, ', '):gsub('%%', '%%%%'))
        vim.cmd('redraw!')
      end

      vim.keymap.set({ 'n', 'x' }, 'm', function()
        local paths = paths_in_range()
        local all_marked = vim.iter(paths):all(function(p) return marks[p] end)
        for _, p in ipairs(paths) do
          marks[p] = not all_marked or nil
        end
        show_marks()
      end, { buffer = true })

      vim.keymap.set('n', 'M', function()
        marks = {}
        show_marks()
      end, { buffer = true })

      vim.keymap.set('x', 'M', function()
        vim.notify('M clears all marks, not a range: m toggles the range, M in normal mode clears all', vim.log.levels.ERROR)
      end, { buffer = true })

      local function accept()
        local selected = vim.deepcopy(marks)
        if in_visual() then
          for _, p in ipairs(paths_in_range()) do
            selected[p] = true
          end
        end
        if vim.tbl_isempty(selected) then
          oil.select()
          return
        end

        local paths = vim.tbl_keys(selected)
        table.sort(paths)
        vim.fn.writefile(vim.tbl_map(resolve_path, paths), tmpfile, 'b') -- 'b': no trailing newline
        vim.cmd('qa!')
      end
      vim.keymap.set({ 'n', 'x' }, '<Tab>', accept, { buffer = true })

      vim.keymap.set({ 'n', 'x' }, '<CR>', function()
        if vim.tbl_isempty(marks) then
          accept()
          return
        end
        local entry = oil.get_cursor_entry()
        if not in_visual() and entry and vim.fn.isdirectory(oil.get_current_dir() .. entry.name) == 1 then
          oil.select()
          return
        end
        vim.notify(('<CR> picks without marks, but %d marked: <Tab> accepts those, m unmarks'):format(vim.tbl_count(marks)),
          vim.log.levels.ERROR)
      end, { buffer = true })

      -- S to jump to Screenshots
      vim.keymap.set('n', 'S', function()
        oil.open(vim.fn.expand('~/tmp/Screenshots/'))
      end, { buffer = true })

      -- <M-b> to open a buffer for manual path entry
      vim.keymap.set('n', '<M-b>', function()
        -- Collect current marks or current directory
        local prefill = vim.tbl_keys(marks)
        if #prefill == 0 then
          table.insert(prefill, oil.get_current_dir())
        end

        -- Create a new scratch buffer
        vim.cmd('enew')
        vim.bo.buftype = 'nofile'
        vim.bo.bufhidden = 'wipe'
        vim.bo.swapfile = false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, prefill)

        -- <CR> or <M-a> to confirm
        local function confirm_paths()
          local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
          local paths = {}
          for _, line in ipairs(lines) do
            local trimmed = line:match('^%s*(.-)%s*$')
            if trimmed and #trimmed > 0 then
              table.insert(paths, trimmed)
            end
          end
          if #paths > 0 then
            vim.fn.writefile(paths, tmpfile)
            vim.cmd('qa!')
          end
        end

        for _, key in ipairs(CONFIRM_KEYS) do
          vim.keymap.set('n', key, confirm_paths, { buffer = true })
        end

        -- Abort keys
        for _, key in ipairs(ABORT_KEYS) do
          vim.keymap.set('n', key, function() vim.cmd('cq') end, { buffer = true })
        end
      end, { buffer = true })

      -- Abort keys
      for _, key in ipairs(ABORT_KEYS) do
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

  -- Get the original suggested filename from the prefilled path
  local original_path = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''
  local original_filename = original_path:match('[^/]+$') or 'file'
  local original_ext = original_filename:match('%.([^.]+)$')

  -- Debug: log to file
  local function log(msg)
    local logf = io.open(vim.fn.expand('~/.local/state/termfilechooser-nvim.log'), 'a')
    if logf then
      logf:write(string.format('%s: %s\n', os.date(), msg))
      logf:close()
    end
  end

  log(string.format('setup_save called, tmpfile=%s, statusfile=%s, original_filename=%s', tmpfile, statusfile, original_filename))

  -- Helper to finalize save with a specific path
  local function finalize_save(path)
    log(string.format('finalize_save path=[%s] to tmpfile=[%s]', path, tmpfile))
    vim.fn.writefile({ path }, tmpfile)
    vim.fn.writefile({ '1' }, statusfile)
    vim.cmd('qa!')
  end

  -- Check if path looks like a directory request (ends with /) or is an existing directory
  local function is_directory_path(path)
    if path:match('/$') then
      return true
    end
    if vim.fn.isdirectory(path) == 1 then
      return true
    end
    return false
  end

  -- Confirm keys
  local function confirm_save()
    -- Get the edited path from buffer
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local path = table.concat(lines, '\n'):match('^%s*(.-)%s*$') -- trim whitespace

    log(string.format('confirm pressed, path=[%s]', path))

    if is_directory_path(path) then
      -- User provided directory - append the original suggested filename
      local dir = path:match('/$') and path or (path .. '/')
      local final_path = dir .. original_filename
      log(string.format('directory detected, using final_path=[%s]', final_path))
      finalize_save(final_path)
    else
      -- If the provided filename has no extension, carry over from original
      local basename = path:match('[^/]+$') or ''
      if original_ext and not basename:match('%.') then
        path = path .. '.' .. original_ext
        log(string.format('extension inferred, final path=[%s]', path))
      end
      finalize_save(path)
    end
  end

  for _, key in ipairs(CONFIRM_KEYS) do
    vim.keymap.set('n', key, confirm_save, { buffer = true })
  end

  -- Abort keys
  for _, key in ipairs(ABORT_KEYS) do
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
