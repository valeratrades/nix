{ ... }: {
  services.blueman.enable = true;

  hardware = {
    bluetooth.hsphfpd.enable = false;
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };
  };

  # Store bluetooth pairing data in home directory
  fileSystems."/var/lib/bluetooth" = {
    device = "/home/v/.local/share/bluetooth";
    fsType = "none";
    options = [ "bind" ];
  };

  # Store NetworkManager connections in home directory
  fileSystems."/etc/NetworkManager/system-connections" = {
    device = "/home/v/.local/share/NetworkManager/system-connections";
    fsType = "none";
    options = [ "bind" ];
  };
}