# HDMI is on the NVIDIA card, which rejects commits while a flip is pending (EBUSY). Unpatched, wlroots drops the gamma LUT of a failed commit for good.
final: prev: {
  wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./wlroots-gamma-retry.patch ];
  });
}
