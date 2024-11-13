battery_saver_icon=""
[ "$(powerprofilesctl get)" = "power-saver" ] && battery_saver_icon="󰌪"

echo "$battery_saver_icon"
