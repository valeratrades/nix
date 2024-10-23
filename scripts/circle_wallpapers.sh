#!/bin/sh

wallpaper_dir="${HOME}/Wallpapers"
#------------------------------------------------------------------------------

file_with_current_wallpaper_ordinal="${HOME}/tmp/.current_wallpaper_ordinal"
mkdir -p $(dirname $file_with_current_wallpaper_ordinal)

if [ -f "$file_with_current_wallpaper_ordinal" ]; then
	CURRENT_WALLPAPER_ORDINAL=$(cat "$file_with_current_wallpaper_ordinal")
else
	CURRENT_WALLPAPER_ORDINAL=1
fi

wallpapers=$(ls "${wallpaper_dir}" | grep -v '^\.' | sort)

n_wallpapers=$(echo -e "$wallpapers" | awk 'END { print NR }')
#if [ $((n_wallpapers % 2)) -eq 0 ]; then
#  notify-send "Due to a weird bug, where circle_wallpapers is evoked twice by sway, you need to keep the num of Wallpapers forever odd. Add another wallpaper to ${wallpaper_dir}"
#fi

get_wallpaper_by_index() {
	i=1
	for wallpaper in $wallpapers; do
		if [ $i -eq $CURRENT_WALLPAPER_ORDINAL ]; then
			echo $wallpaper
			return
		fi
		i=$((i + 1))
	done
}

update_wallpaper() {
	wallpaper=$(get_wallpaper_by_index)
	swaymsg output '*' background "${wallpaper_dir}/${wallpaper}" fill
	echo $CURRENT_WALLPAPER_ORDINAL > "$file_with_current_wallpaper_ordinal"
}

next() {
	CURRENT_WALLPAPER_ORDINAL=$((CURRENT_WALLPAPER_ORDINAL % n_wallpapers + 1))
	update_wallpaper
}
prev() {
	CURRENT_WALLPAPER_ORDINAL=$((CURRENT_WALLPAPER_ORDINAL - 1))
	if [ $CURRENT_WALLPAPER_ORDINAL -le 0 ]; then
		CURRENT_WALLPAPER_ORDINAL=$n_wallpapers
	fi
	update_wallpaper
}
case "$1" in
	f) next ;;
	b) prev ;;
	*) printf "\033[31mPossible commands: [ f, b ]\033[0m\n"
esac
