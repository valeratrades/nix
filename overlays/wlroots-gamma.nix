# nvidia-drm returns EBUSY on a nonblocking commit while the previous LUT upload is in flight (HDMI is on the NVIDIA card); unpatched wlroots then drops that frame together with its gamma LUT.
final: prev: {
  wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./wlroots-gamma-retry.patch ];
  });
}
