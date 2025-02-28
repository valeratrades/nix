{ pkgs, ... }: {
  programs = {
    chromium = {
      enable = true;
      package = pkgs.chromium;
      extensions = [
        { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; } # vimium
      ];
    };
  };
}
