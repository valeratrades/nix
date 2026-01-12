{ self
, config
, lib
, pkgs
, inputs
, mylib
, user
, ...
}:
{
  home.packages =
    with pkgs;
    builtins.trace "DEBUG: sourcing Masha-specific home.nix" lib.lists.flatten
      [
        [
          # embedded dev
          #platformio-core #dbg: doesn't work rn for some reason
          #platformio #dbg: couldn't build the `pio` thing for some reason
          #arduino #dbg: can't build for some reason
          arduino-core
          arduino-ci
          arduino-mk
          arduino-ide
          arduino-language-server
          cargo-pio
          vscode-extensions.platformio.platformio-vscode-ide
          minicom
        ]
      ];
}
