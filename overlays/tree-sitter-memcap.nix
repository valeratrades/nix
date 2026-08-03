# A runaway Verse grammar made `tree-sitter parse` reach 40G RSS, drain 64G of swap and
# take the desktop down with it (earlyoom SIGTERM'd it 24x, it never responded).
# ponytail: RLIMIT_AS, not a cgroup — needs no session bus, so it also holds under
# nix build sandboxes and bare ssh. Raise if a legitimate corpus ever needs more.
final: prev:
{
  # overrideAttrs rather than a symlinkJoin wrapper: neovim-nightly-overlay reaches into
  # this derivation's pname, which a join would drop.
  tree-sitter = prev.tree-sitter.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/tree-sitter --run 'ulimit -v 8388608'
    '';
  });
}
