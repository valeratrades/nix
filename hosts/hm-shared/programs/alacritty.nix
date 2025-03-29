{ self, user, lib, ... }: {
  home.file = {
    ".config/alacritty/themes" = {
      source = "${self}/home/config/alacritty/themes";
      recursive = true;
    };
    ".config/alacritty/README.md" = {
      source = "${self}/home/config/alacritty/README.md";
    };
    ".config/alacritty/alacritty.toml.hm" = {
      #mode = "0666"; //hm can't yet work with modes
      #NB: impossible to properly gen until I figure out how to escape `"\u0017"`. // currently ends up as either "u0017" or "\\u0017"
      text = ''
        #tabspaces = 2

        #NB: opacity is defined separately in the colorschemes

        [cursor]
        blink_interval = 500
        blink_timeout = 0
        thickness = 0.4
        unfocused_hollow = true

        [env]
        TERM = "xterm-256color"

        [font]
        builtin_box_drawing = true
        size = ${toString user.fontSize}

        [font.bold]
        family = "monospace"

        [font.bold_italic]
        family = "monospace"

        [font.italic]
        family = "monospace"

        [font.normal]
        family = "monospace"
        style = "Regular"

        [[keyboard.bindings]]
        chars = "\u0017"
        key = "Back"
        mods = "Control"

        [[keyboard.bindings]]
        action = "ScrollHalfPageUp"
        key = "Up"
        mods = "Alt"

        [[keyboard.bindings]]
        action = "ScrollHalfPageDown"
        key = "Down"
        mods = "Alt"

        [[keyboard.bindings]]
        action = "ScrollToTop"
        key = "G"
        mods = "Alt"

        [[keyboard.bindings]]
        action = "ScrollToBottom"
        key = "G"
        mods = "Shift|Alt"

        [[keyboard.bindings]]
        action = "IncreaseFontSize"
        key = "Equals"
        mods = "Control"

        [[keyboard.bindings]]
        action = "IncreaseFontSize"
        key = "Plus"
        mods = "Control"

        [[keyboard.bindings]]
        action = "DecreaseFontSize"
        key = "Minus"
        mods = "Control"

        [scrolling]
        history = 10000
        multiplier = 5

        [selection]
        save_to_clipboard = true

        [window]
        decorations = "none"
        dynamic_title = true
        resize_increments = true
        title = "Alacritty"

        [window.class]
        general = "Alacritty"
        instance = "Alacritty"

        [window.padding]
        x = 0
        y = 0

        [general]
        live_config_reload = true
        import = ["/home/${user.username}/.config/alacritty/themes/github_dark.toml"]
        		'';
    };
  };
  home.activation = {
    alacritty = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            cp ~/.config/alacritty/alacritty.toml.hm ~/.config/alacritty/alacritty.toml
      			chmod 666 ~/.config/alacritty/alacritty.toml
    '';
  };
}
