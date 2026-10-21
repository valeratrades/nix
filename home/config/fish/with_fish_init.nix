# Bakes `<cmd> | source` output of a clap tool into its package, so shell startup evaluates none of it:
# completions autoload on first Tab, aliases autoload on first call.
pkgs: { pkg, cmd, postBuild ? "" }:
pkgs.symlinkJoin {
  inherit (pkg) name meta;
  paths = [ pkg ];
  nativeBuildInputs = [ pkgs.fish ];
  postBuild = ''
    export HOME=$TMPDIR # tools write logs/config under it
    exe=${builtins.head (pkgs.lib.splitString " " cmd)}
    PATH=$out/bin:$PATH ${cmd} > $TMPDIR/init.fish

    n=$(grep -n -m1 -F '# Print an optspec for argparse' $TMPDIR/init.fish | cut -d: -f1)
    [ -n "$n" ] || { echo "no clap completions in \`${cmd}\` output" >&2; exit 1; }
    head -n $((n - 1)) $TMPDIR/init.fish > $TMPDIR/aliases.fish
    if grep -vE '^[[:space:]]*(#.*)?$|^alias ' $TMPDIR/aliases.fish; then
      echo "\`${cmd}\` emits more than aliases before its completions; that part would have to be sourced at startup" >&2
      exit 1
    fi

    mkdir -p $out/share/fish/vendor_completions.d $out/share/fish/vendor_functions.d
    tail -n +$n $TMPDIR/init.fish > $out/share/fish/vendor_completions.d/$exe.fish
    fish --no-config -c '
      functions -q alias # autoload it before snapshotting
      set -l before (functions -an)
      source $argv[1]
      for f in (functions -an)
        contains -- $f $before; or functions $f > $argv[2]/$f.fish
      end
    ' $TMPDIR/aliases.fish $out/share/fish/vendor_functions.d
  '' + postBuild;
}
