# wtype hands out keycodes 1..N in order of first use, and Chromium reads those as physical
# keys: pasting text with enough distinct chars sent F5/Ctrl/Alt/Power/BrowserBack into Chrome.
final: prev: {
  wtype = prev.wtype.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./wtype-safe-keycodes.patch ];
  });
}
