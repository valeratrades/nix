{ lib, ... }:
let
  # Helper function to create symlink activation scripts
  mkSymlink = args:
    let
      # If target_path is provided, use it directly along with config_path
      # Otherwise, construct both paths from target_path_postfix
      targetPath =
        if args ? target_path
        then args.target_path
        else "$XDG_CONFIG_HOME/${args.target_path_postfix}";

      configPath =
        if args ? config_path
        then args.config_path
        else "$NIXOS_CONFIG/home/config/${args.target_path_postfix}";
    in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      [ -e "${targetPath}" ] || ln -sf "${configPath}" "${targetPath}"
    '';
in
{
  # fuck mkOutOfStoreSymlink and home-manager. Just link everything except for where apps like to write artifacts to the config dir.
  home.activation = {
    nvim = mkSymlink { target_path_postfix = "nvim"; };
    eww = mkSymlink { target_path_postfix = "eww"; };
    site = mkSymlink { target_path_postfix = "site.nix"; };
    sway = mkSymlink { target_path_postfix = "sway"; };
    btc_line = mkSymlink { target_path_postfix = "btc_line.nix"; };
    social_networks = mkSymlink { target_path_postfix = "social_networks.toml"; };
    claude_code_global_CLAUDE_md = mkSymlink {
      target_path = "$HOME/.claude/CLAUDE.md";
      config_path = "$NIXOS_CONFIG/home/config/claude/CLAUDE.md";
    };
    rm_engine = mkSymlink { target_path_postfix = "rm_engine.nix"; };
    wallpaper_carousel = mkSymlink { target_path_postfix = "wallpaper_carousel.nix"; };
    discretionary_engine = mkSymlink { target_path_postfix = "discretionary_engine.nix"; };
    shared = mkSymlink { target_path_postfix = "shared"; };
  };
}
