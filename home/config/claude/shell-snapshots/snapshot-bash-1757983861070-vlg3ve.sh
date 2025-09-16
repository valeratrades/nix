# Snapshot file
# Unset all aliases to avoid conflicts with functions
unalias -a 2>/dev/null || true
shopt -s expand_aliases
# Check for rg availability
if ! command -v rg >/dev/null 2>&1; then
  alias rg='/nix/store/lkfs8kd90a2ij1ngsrjqm8dgq3f9m0sy-claude-code-1.0.107/lib/node_modules/\@anthropic-ai/claude-code/vendor/ripgrep/x64-linux/rg'
fi
export PATH=/run/wrappers/bin\:/home/v/.nix-profile/bin\:/nix/profile/bin\:/home/v/.local/state/nix/profile/bin\:/etc/profiles/per-user/v/bin\:/nix/var/nix/profiles/default/bin\:/run/current-system/sw/bin
