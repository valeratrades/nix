{ ... }: {
  services.blueman.enable = true;

  hardware = {
    bluetooth.hsphfpd.enable = false;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}