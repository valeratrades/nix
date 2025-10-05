{ ... }: {
  services = {
    gvfs.enable = true; # Mount, trash, and other functionalities
    tumbler.enable = true; # Thumbnail support for images
    geoclue2.enable = true; # Enable geolocation services
    printing.enable = true; # Enable CUPS to print documents
  };
}