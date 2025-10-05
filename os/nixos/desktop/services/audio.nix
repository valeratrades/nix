{ ... }: {
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = false;
    jack.enable = true;
    wireplumber.enable = true;
  };
}