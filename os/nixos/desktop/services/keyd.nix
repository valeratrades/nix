{ ...
}:
{
  services.keyd = {
    enable = true;
    # keyd expects qwerty keypresses and receives exact keycodes, so since I use semimak, here are defined the qwerty names of the keys I'm actually pressing (enormously confusing all the way)
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          global = {
            macro_timeout = 200;
            oneshot_timeout = 120;
          };
          main = {
            leftcontrol = "capslock";
            capslock = "overload(ctrl_vim, esc)";
            shift = "oneshot(shift)";
            alt = "oneshot(alt)";
            "102nd" = "oneshot(shift)";
          };
          "ctrl_vim:C" = {
            space = "swap(vim_mode)";
            x = "cut";
            c = "copy";
            v = "paste";
            delete = "C-delete";
            backspace = "C-backspace";
          };
          # easier to reach then ones in ctrl_vim, but can't add full functionality here. So movement keys are accessible both ways.
          alt = {
            a = "left";
            s = "down";
            d = "up";
            f = "right";
          };
          "vim_mode:C" = {
            space = "swap(ctrl_vim)";
            a = "left";
            s = "down";
            d = "up";
            f = "right";
            c = "C-left";
            k = "C-right";
            u = "macro(C-right right)";
            x = "cut";
            # copy is overwritten by now 'b' (on semimak), so you'd switch back or use the actual 'c' on semimak for this
            v = "paste";
            delete = "C-delete";
            backspace = "C-backspace";
            # `C-{arrow}` couldn't care less for the start of the line; and just goes right past it. Although is useful for quick nav across long lines in the terminal.
            l = "macro(C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right C-right)";
            ";" =
              "macro(C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left C-left)";
          };
          shift = {
            backspace = "C-backspace";
            #NOTE: assumes backspace is on AltGr. Will lead to unintended consiquences if not!
            rightalt = "C-backspace";
            delete = "C-delete";
          };
        };
      };
    };
  };
}
