#!/bin/sh

sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.tmp
sudo sh -c "rankmirrors -n 10 /etc/pacman.d/mirrorlist.tmp > /etc/pacman.d/mirrorlist"
