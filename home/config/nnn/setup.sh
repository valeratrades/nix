#!/bin/sh
# incredible tutorial: https://www.youtube.com/embed/-knZwdd1ScU
# https://github.com/jarun/nnn/wiki/Advanced-use-cases
#?? https://github.com/GermainZ/xdg-desktop-portal-termfilechooser

export QT_QPA_PLATFORMTHEME=flatpak
export GTK_USE_PORTAL=1
export GDK_DEBUG=portals

#export FILE=nnn
#export NNN_OPENER='xdg-open'

# install or update the plugins
#sh -c "$(curl -Ls https://raw.githubusercontent.com/jarun/nnn/master/plugins/getplugs)"
NNN_FIFO="/tmp/nnn.fifo"; export NNN_FIFO # crucial for some plugins


export NNN_PLUG='g:dragdrop;u:davecloud;f:finder;o:fzopen;j:jump;c:fcd;d:diffs;m:nmount;v:imgview;p:preview-tui;t:preview-tabbed'
#NNN_FCOLORS='0000E6310000000000000000'
export NNN_OPTS="H" # hiddden files shown. (toggle with `.`)
export NNN_PREFER_SELECTION=1
export NNN_PREVIEWIMGPROG="feh"
alias nnn="nnn -e"
