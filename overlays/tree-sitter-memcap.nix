# A runaway Verse grammar made `tree-sitter parse` reach 40G RSS, drain 64G of swap and
# take the desktop down with it (earlyoom SIGTERM'd it 24x, it never responded).
# ponytail: RLIMIT_AS, not a cgroup — needs no session bus, so it also holds under
# nix build sandboxes and bare ssh. Raise if a legitimate corpus ever needs more.
final: prev:
{
  tree-sitter = prev.symlinkJoin {
    name = "tree-sitter-memcapped-${prev.tree-sitter.version}";
    paths = [ prev.tree-sitter ];
    nativeBuildInputs = [ prev.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/tree-sitter --run 'ulimit -v 8388608'
    '';
    inherit (prev.tree-sitter) meta passthru;
  };
}
