#!/bin/sh

## (in kilobytes, so 30GB)
#pacman_cache_threshold=30000000
#pacman_cache_size=$(du -sk /var/cache/pacman/pkg | cut -f1)
#if [ "$pacman_cache_size" -gt "$pacman_cache_threshold" ]; then
#	sudo pacman -Sc --noconfirm
#	echo "\033[32mCleaned pacman cache\033[0m"
#
#	echo "\033[31mMirrorls are likely to be stale, refreshing (hold tight, will take about 20m)\033[0m"
#	sudo sh ./update_full_mirrorlist.sh
#	echo "\033[32mRefreshed mirrorlist\033[0m"
#fi

# (in kilobytes, so 20GB)
home_cache_threshold=20000000
home_cache_size=$(sudo du -sk /home/v/.cache | cut -f1)
if [ "$home_cache_size" -gt "$home_cache_threshold" ]; then
	rm -rf /home/v/.cache/*
	echo "\033[32mCleaned home cache\033[0m"
fi
