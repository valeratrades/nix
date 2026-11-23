{ ... }:
{
  xdg = {
    mime = {
      enable = true;
      defaultApplications = {
        "application/pdf" = "org.pwmt.zathura.desktop";
        "text/markdown" = "nvim_alacritty.desktop";
        "text/plain" = "nvim_alacritty.desktop";
        "inode/directory" = "nvim_alacritty.desktop"; # vscodium claims both in its .desktop
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "libreoffice-calc.desktop";
      };
    };
  };
}
