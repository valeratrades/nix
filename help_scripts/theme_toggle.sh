#!/bin/sh

CURRENT_MODE=$(gsettings get org.gnome.desktop.interface color-scheme)
#dark_theme_alacritty="rose-pine"
#light_theme_alacritty="catppuccino-latte"
dark_theme_alacritty="github_dark"
light_theme_alacritty="github_light_high_contrast"

if [ "$CURRENT_MODE" = "'prefer-dark'" ]; then
	notify-send "going light"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
  sed -i "s/${dark_theme_alacritty}.toml/${light_theme_alacritty}.toml/" ~/.config/alacritty/alacritty.toml
	swaymsg output '*' bg ~/Wallpapers/AndreySakharov.jpg fill
else
	notify-send "going dark"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  sed -i "s/${light_theme_alacritty}.toml/${dark_theme_alacritty}.toml/" ~/.config/alacritty/alacritty.toml
	swaymsg output '*' bg ~/Wallpapers/girl_with_a_perl_earring.jpg fill
fi
nvim --remote-send '<C-\><C-N>:lua setSystemTheme()<CR>'
