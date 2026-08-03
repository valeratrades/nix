{ pkgs
, mylib
, ...
}:
{
  environment.shellAliases.wui = "waydroid show-full-ui"; # main entry point
  # webkitgtk scare was gnome-boxes, not waydroid — closure is clean.
  virtualisation.waydroid.enable = true;
	##NB: must run init manually as follows:
 # #- init with `sudo waydroid init -s GAPSS -f`
 # #- patch google-play certificate: https://docs.waydro.id/faq/google-play-certification
 # # normally setup also requires modyfiying waydroid_base.prop and starting up `systemctl wayland-container`, but these are taken care of below.
 # system.activationScripts.patchWaydroid = {
 #   text = ''
 #     # if the patch was already appplied, testing reversing it (\`--dry-run -R\`) returns 0
 #     if ! ${pkgs.patch}/bin/patch --dry-run -R "/var/lib/waydroid/waydroid_base.prop" < ${(mylib.relativeToRoot "os/nixos/desktop/waydroid/waydroid_base.prop.diff")} >/dev/null 2>&1; then
 #       ${pkgs.patch}/bin/patch "/var/lib/waydroid/waydroid_base.prop" < ${(mylib.relativeToRoot "os/nixos/desktop/waydroid/waydroid_base.prop.diff")}
 #     fi
 #   '';
 # };
}
