# gtk 4.20 drops stylus tip-down on wayland, so pen never draws (flxzt/rnote#1543). Fixed in gtk >=4.21.4; drop once nixpkgs gtk4 has it.
final: prev: {
  rnote = prev.rnote.override {
    gtk4 = prev.gtk4.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (prev.fetchpatch {
          url = "https://gitlab.gnome.org/GNOME/gtk/-/commit/323484d8024f94dc26eb2d00694ccd51fe330c0e.diff";
          hash = "sha256-4jWqFEs8gvQVAItX5qmlcF04iZ6gZhiOAevcNDYGIqA=";
        })
      ];
    });
  };
}
