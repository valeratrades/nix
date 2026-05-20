-- Commit-scoped file viewing.
-- When opening a file from lazygit's commit-files panel, we get the commit SHA
-- and call gitsigns.change_base to scope all hunk signs/nav to that commit's diff.
--
-- IPC via tempfile: lazygit customCommand writes /tmp/nvim-commit-view,
-- this module's timer picks it up.

local M = {}

local TRIGGER_FILE = '/tmp/nvim-commit-view'
local POLL_MS = 200

-- ---------------------------------------------------------------------------
-- Poll the trigger file (written by lazygit's customCommand)
-- ---------------------------------------------------------------------------

local function start_polling()
  local timer = vim.uv.new_timer()
  if not timer then
    return -- uv unavailable
  end

  timer:start(0, POLL_MS, vim.schedule_wrap(function()
    local f = io.open(TRIGGER_FILE, 'r')
    if not f then
      return
    end

    local line = f:read('*l')
    f:close()
    os.remove(TRIGGER_FILE)

    if not line or line == '' then
      return
    end

    -- Format: <sha> <path>
    local sha, path = line:match('^(%S+)%s+(.+)$')
    if not sha or not path then
      vim.notify('CommitView: malformed trigger line: ' .. line, vim.log.levels.ERROR)
      return
    end

    M.open(sha, path)
  end))
end

-- ---------------------------------------------------------------------------
-- Open
-- ---------------------------------------------------------------------------

function M.open(sha, path)
  -- When triggered from lazygit's float, we're in the terminal window.
  -- Close it so the file opens in the real window underneath.
  if vim.g.lazygit_opened == 1 then
    pcall(vim.cmd, 'close')
    vim.g.lazygit_opened = 0
  end

  -- Restore to repo-root cwd so relative paths resolve correctly
  if vim.env.PWD then
    pcall(vim.cmd, 'cd ' .. vim.fn.fnameescape(vim.env.PWD))
  end

  -- Path from lazygit is relative to repo root
  vim.cmd('edit ' .. vim.fn.fnameescape(path))

  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].commit_view_sha = sha
  vim.b[buf].commit_view_path = path

  M._attach(buf, sha)
end

-- ---------------------------------------------------------------------------
-- Attach commit-scoped gitsigns + buffer-local keymaps
-- ---------------------------------------------------------------------------

function M._attach(buf, sha)
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if vim.b[buf].commit_view_sha ~= sha then
      return -- buffer reused for another file (quick successive opens)
    end

    local ok, gs = pcall(require, 'gitsigns')
    if not ok or not gs then
      return
    end

    gs.change_base(sha .. '^')
  end, 200)

  -- Buffer-local Telescope picker: files changed in this commit
  K('n', '<Space>gm', function()
    M._pick_files(sha)
  end, { buffer = buf, desc = 'Git: files in commit ' .. sha:sub(1, 8) })

  -- Revert to normal gitsigns base (HEAD)
  K('n', '<Space>gR', function()
    local ok, gs = pcall(require, 'gitsigns')
    if ok then
      gs.change_base(nil)
    end
    vim.b[buf].commit_view_sha = nil
    vim.b[buf].commit_view_path = nil
    vim.notify('Gitsigns base reset to HEAD', vim.log.levels.INFO)
  end, { buffer = buf, desc = 'Git: reset diff base to HEAD' })
end

-- ---------------------------------------------------------------------------
-- Telescope picker: files changed in this commit
-- ---------------------------------------------------------------------------

function M._pick_files(sha)
  local out = vim.fn.systemlist({
    'git', 'diff-tree', '--no-commit-id', '--name-status', '-r', sha
  })

  if vim.v.shell_error ~= 0 or #out == 0 then
    vim.notify('No changed files in commit ' .. sha:sub(1, 8), vim.log.levels.WARN)
    return
  end

  local entries = {}
  for _, line in ipairs(out) do
    local parts = vim.split(line, '\t', { plain = true })
    if #parts >= 2 then
      local status = parts[1]
      -- For renames (Rxxx) and copies (Cxxx), the last field is the new path
      local filepath = parts[#parts]
      table.insert(entries, { status = status, path = filepath })
    end
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Files in ' .. sha:sub(1, 8),
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        return {
          value = e.path,
          ordinal = e.path,
          display = string.format('%-2s  %s', e.status, e.path),
          path = e.path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then
          M.open(sha, sel.value)
        end
      end)
      return true
    end,
  }):find()
end

-- ---------------------------------------------------------------------------
-- Exposed commands
-- ---------------------------------------------------------------------------

-- Direct invocation: :CommitView <sha> <path>
vim.api.nvim_create_user_command('CommitView', function(opts)
  if #opts.fargs < 2 then
    vim.notify(':CommitView <sha> <path>', vim.log.levels.ERROR)
    return
  end
  M.open(opts.fargs[1], table.concat(opts.fargs, ' ', 2))
end, { nargs = '+' })

-- Reset base to HEAD for current buffer
vim.api.nvim_create_user_command('CommitViewClose', function()
  local buf = vim.api.nvim_get_current_buf()
  local sha = vim.b[buf].commit_view_sha
  if not sha then
    vim.notify('Not in a commit-view buffer', vim.log.levels.WARN)
    return
  end
  local ok, gs = pcall(require, 'gitsigns')
  if ok then
    gs.change_base(nil)
  end
  vim.b[buf].commit_view_sha = nil
  vim.b[buf].commit_view_path = nil
  vim.notify('Commit view closed', vim.log.levels.INFO)
end, {})

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

-- Clear stale trigger file from a previous session
os.remove(TRIGGER_FILE)

-- Start file poller immediately on module load
start_polling()

return M
