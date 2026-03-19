{ user, ... }: {
  programs.ghostty = {
    enable = true;
    settings = {
      confirm-close-surface = false;
      theme = "none";

      font-family = "monospace";
      font-style = "Regular";
      font-size = user.fontSize;
      adjust-font-size-when-changing-dpi = false;

      cursor-style = "bar";
      cursor-style-blink = true;

      window-decoration = false;
      window-padding-x = 0;
      window-padding-y = 0;

      scrollback-limit = 10000;

      background = "000000";
      foreground = "d1d5da";

      palette = [
        "0=#586069"
        "1=#ea4a5a"
        "2=#34d058"
        "3=#ffea7f"
        "4=#2188ff"
        "5=#b392f0"
        "6=#39c5cf"
        "7=#d1d5da"
        "8=#959da5"
        "9=#f97583"
        "10=#85e89d"
        "11=#ffea7f"
        "12=#79b8ff"
        "13=#b392f0"
        "14=#56d4dd"
        "15=#fafbfc"
        "16=#d18616"
        "17=#f97583"
      ];

      keybind = [
        "ctrl+backspace=text:\\x17"
        "alt+up=scroll_page_up"
        "alt+down=scroll_page_down"
        "alt+g=scroll_to_top"
        "alt+shift+g=scroll_to_bottom"
        "ctrl+equal=increase_font_size:1"
        "ctrl+plus=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
      ];
    };
  };
}
