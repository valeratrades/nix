# A runaway Verse grammar made `tree-sitter parse` reach 40G RSS, drain 64G of swap and
# take the desktop down with it (earlyoom SIGTERM'd it 24x, it never responded).
# ponytail: RLIMIT_AS, not a cgroup — needs no session bus, so it also holds under bare ssh.
# Raise if a legitimate corpus ever needs more.
final: prev:
{
  # own attr rather than overriding `tree-sitter`: that would rebuild every libtree-sitter consumer (neovim, emacs) off-cache
  tree-sitter-capped = prev.writeShellScriptBin "tree-sitter" ''
    ulimit -v 8388608
    exec ${prev.tree-sitter}/bin/tree-sitter "$@"
  '';
}
