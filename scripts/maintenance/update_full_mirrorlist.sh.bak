#!/bin/sh
#NB: likely to take about 20m

sudo curl -o /etc/pacman.d/mirrorlist.new https://archlinux.org/mirrorlist/all/
sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.new
sudo rankmirrors -n 10 /etc/pacman.d/mirrorlist.new | sudo tee /etc/pacman.d/mirrorlist
