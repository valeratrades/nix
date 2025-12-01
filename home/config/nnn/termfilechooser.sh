#!/bin/sh
# File chooser wrapper for xdg-desktop-portal-termfilechooser
# Arguments from portal: $1=dir, $2=multiple, $3=save, $4=suggestion, $5=output_file
# save=0 means OPEN, save=1 means SAVE

dir="${1:-$HOME}"
multiple="$2"
save="$3"
suggestion="$4"
out="$5"

# Debug notifications (uncomment to debug)
# notify-send "termfilechooser" "save: $save, dir: $dir, suggestion: $suggestion, out: $out"

if [ "$save" -eq 0 ]; then
  # Open mode: use nvim normally to browse and select a file
  # When user "opens" a file, capture the path instead of actually opening it

  # Start in the suggested directory or fallback to dir
  if [ -d "$suggestion" ]; then
    startdir="$suggestion"
  else
    startdir="$dir"
  fi

  # Create a temp file to store the selected file path
  tmpfile=$(mktemp)

  # Open nvim on startdir, but don't cd (so cwd stays at ~/)
  alacritty -e nvim "$startdir" \
    -c "lua _G.filechooser_marks = {}; _G.filechooser_ns = vim.api.nvim_create_namespace('filechooser'); vim.api.nvim_create_autocmd('BufReadPre', { callback = function(args) local file = vim.fn.expand('<afile>:p'); if vim.fn.filereadable(file) == 1 then local f = io.open('$tmpfile', 'w'); if f then f:write(file); f:close(); end; vim.cmd('qa!'); end; return true; end })" \
    -c "lua vim.api.nvim_create_autocmd('FileType', { pattern = 'oil', callback = function(ev) local oil = require('oil'); vim.keymap.set('n', 's', function() local entry = oil.get_cursor_entry(); if entry and entry.type == 'file' then local path = oil.get_current_dir() .. entry.name; local lnum = vim.fn.line('.'); if _G.filechooser_marks[path] then _G.filechooser_marks[path] = nil; vim.api.nvim_buf_clear_namespace(ev.buf, _G.filechooser_ns, lnum-1, lnum); else _G.filechooser_marks[path] = true; vim.api.nvim_buf_set_extmark(ev.buf, _G.filechooser_ns, lnum-1, 0, { sign_text = '*', sign_hl_group = 'DiagnosticSignWarn' }); end; end end, { buffer = true }); vim.keymap.set('n', '<CR>', function() local paths = {}; for p in pairs(_G.filechooser_marks) do table.insert(paths, p); end; if #paths == 0 then local entry = oil.get_cursor_entry(); if entry and entry.type == 'file' then paths = { oil.get_current_dir() .. entry.name }; end; end; if #paths > 0 then local f = io.open('$tmpfile', 'w'); if f then for i, p in ipairs(paths) do f:write(p); if i < #paths then f:write('\\n'); end; end; f:close(); end; vim.cmd('qa!'); end; end, { buffer = true }); vim.keymap.set('v', '<CR>', function() local oil = require('oil'); local dir = oil.get_current_dir(); local start_line = vim.fn.line('v'); local end_line = vim.fn.line('.'); if start_line > end_line then start_line, end_line = end_line, start_line; end; local paths = {}; for lnum = start_line, end_line do local entry = oil.get_entry_on_line(0, lnum); if entry and entry.type == 'file' then table.insert(paths, dir .. entry.name); end; end; if #paths > 0 then local f = io.open('$tmpfile', 'w'); if f then for i, p in ipairs(paths) do f:write(p); if i < #paths then f:write('\\n'); end; end; f:close(); end; vim.cmd('qa!'); end; end, { buffer = true }); vim.keymap.set('n', 'S', function() oil.open(vim.fn.expand('~/tmp/Screenshots/')) end, { buffer = true }); end })"

  # Read the selected file path
  if [ -f "$tmpfile" ] && [ -s "$tmpfile" ]; then
    cat "$tmpfile" > "$out"
  fi

  rm -f "$tmpfile"
else
  # Save mode: let user edit the filename directly in nvim
  if [ -n "$suggestion" ]; then
    echo "$suggestion" > "$out"
  else
    echo "$dir/newfile" > "$out"
  fi

  # Open with q mapped to just exit, Enter to confirm and save
  alacritty -e nvim "$out" \
    -c 'nnoremap <CR> :wq<CR>' \
    -c 'nnoremap q :qa!<CR>'
fi
