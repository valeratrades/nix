function chh
    sudo chmod -R 777 ~/
end

function usb
    set partition (or $argv[1] "/dev/sdb1")
    sudo mkdir -p /mnt/usb
    sudo chown (whoami):(whoami) /mnt/usb
    sudo mount -o rw $partition /mnt/usb
    cd /mnt/usb
    exa -A
end

function creds
    set _dir "$HOME/s/g/private/"
    git -C $argv[1] pull > /dev/null 2>&1
    nvim "$_dir/credentials.fish"
    git -C $_dir add -A; and git -C $_dir commit -m "."; and git -C $_dir push
end

function lg
    if test (count $argv) = 1
        ls -lA | rg $argv[1]
    else if test (count $argv) = 2
        ls -lA $argv[1] | rg $argv[2]
    end
end

function fz
    fd $argv | jfind
end

# sync dots
function sd
    $HOME/.dots/main.sh sync $argv > /tmp/dots_log.txt 2>&1 &
end

function chess
    source $HOME/envs/Python/bin/activate
    py -m cli_chess --token lip_sjCnAuNz1D3PM5plORrC
end

# move head
function mvt
    set from "."
    set to $argv[1]
    if test $argv[1] = "-p" -o $argv[1] = "--paper"
        set from "$HOME/Downloads"
        set to "$HOME/Documents/Papers"
    else if test $argv[1] = "-b" -o $argv[1] = "--book"
        set from "$HOME/Downloads"
        set to "$HOME/Documents/Books"
    else if test $argv[1] = "-n" -o $argv[1] = "--notes"
        set from "$HOME/Downloads"
        set to "$HOME/Documents/Notes"
    else if test $argv[1] = "-c" -o $argv[1] = "--courses"
        set from "$HOME/Downloads"
        set to "$HOME/Documents/Courses"
    else if test $argv[1] = "-w" -o $argv[1] = "--wine"
        set from "$HOME/Downloads"
        set to "$HOME/.wine/drive_c/users/v/Downloads"
    end
    
    mv "$from/(ls $from -t | head -n 1)" $to
end

function matrix
    function cleanup
        sed -i "s/#import =/import =/" ~/.config/alacritty/alacritty.toml
    end

    trap cleanup EXIT
    trap cleanup INT

    sed -i "s/import =/#import =/" ~/.config/alacritty/alacritty.toml
    unimatrix -s96 -fa
    cleanup
end

alias fd="fd -I --full-path" # Ignores .gitignore, etc.
alias rg="rg -I --glob '!.git'" # Ignores case sensitivity and .git directories.
alias ureload="pkill -u (whoami)" # Kill all processes of the current user.
alias rf="sudo rm -rf"
alias srf="sudo rm -rf"
alias za="zathura"
alias zp="zathura --mode presentation"
alias massren="py $HOME/clone/massren/massren -d '' $argv"
alias q="py $HOME/s/help_scripts/ask_gpt.py -s $argv"
alias f="py $HOME/s/help_scripts/ask_gpt.py -f $argv"
alias jp="jupyter lab -y"
alias sr="source ~/.config/fish/config.fish" # Fish equivalent for reloading configuration.
alias tree="tree -I 'target|debug|_*'"
alias lhost="nohup nyxt http://localhost:8080/ > /dev/null 2>&1 &"
alias ll="exa -lA"
alias sound="qpwgraph"
alias choose_port="$HOME/s/help_scripts/choose_port.sh"
alias obs="mkdir ~/Videos/obs >/dev/null; sudo modprobe v4l2loopback video_nr=2 card_label=\"OBS Virtual Camera\" && pamixer --default-source --set-volume 70 && obs"
alias video_cut="video-cut"
alias ss="sudo systemctl"
alias cl="wl-copy"
alias wl_copy="wl-copy"
alias gz="tar -xvzf -C"
alias toggle_theme="$HOME/s/help_scripts/theme_toggle.sh"
alias tokej="tokei -o json | jq . > /tmp/tokei.json"
alias book="booktyping run --myopia"
alias tokio-console="tokio-console --lang en_US.UTF-8"
alias tokio_console="tokio-console"
alias fm="yazi" # File manager
alias t="ls -t | head -n 1"
alias mongodb="mongosh \"mongodb+srv://test.di2kklr.mongodb.net/\" --apiVersion 1 --username valeratrades --password qOcydRtmgFfJnnpd"
alias sql="sqlite3"
alias poetry="POETRY_KEYRING_DISABLED=true poetry"
alias dk="sudo docker"
alias hardware="sudo lshw"
alias home_wifi="nmcli connection up id \"Livebox-3B70\"" # dbg
alias keys="xev -event keyboard"
alias audio="qpwgraph"
alias test_mic="arecord -c1 -vvv /tmp/mic.wav"
alias nano="nvim"
alias pro_audio="pulsemixer"
alias wayland_wine="DISPLAY='' wine64" # Set up to work with Wayland
alias pfind="procs --tree | fzf"
alias tree="fd . | as-tree"
alias bak="XDG_CONFIG_HOME=/home/v/.dots/home/v/.config"
alias as_term="script -qfc"
alias bluetooth="blueman-manager"
alias wget="aria2c -x16"
alias disable_fan="echo 0 | sudo tee /sys/class/hwmon/hwmon6/pwm1"
alias enable_fan="echo 2 | sudo tee /sys/class/hwmon/hwmon6/pwm1"
alias phone-wifi="sudo nmcli dev wifi connect Valera password 12345678"
alias phone_wifi="phone-wifi"


# # fish
alias where="functions --details"
#

# # nix
alias nix-build="sudo nixos-rebuild switch --show-trace -L -v --impure" #HACK: using impure
alias flake-build="sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v"
#


#gpg id = gpg --list-keys --with-colons | awk -F: '/uid/ && /valeratrades@gmail.com/ {getline; print $5}'

# # keyd
alias rkeyd="sudo keyd reload && sudo journalctl -eu keyd"
alias lkeyd="sudo keyd -m"
#

# # help_scripts
alias beep="$HOME/s/help_scripts/beep.sh"
alias timer="$HOME/s/help_scripts/timer.sh"
#

#TODO!: figure out direnv
#direnv hook fish | source
