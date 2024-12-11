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
alias za="zathura"
alias zp="zathura --mode presentation"
#alias massren="py $HOME/clone/massren/massren -d '' $argv"
alias jp="jupyter lab -y"
#alias tree="tree -I 'target|debug|_*'"
alias tree="eza --tree"
alias lhost="nohup nyxt http://localhost:8080/ > /dev/null 2>&1 &"
alias sound="qpwgraph"
#alias obs="mkdir ~/Videos/obs >/dev/null; sudo modprobe v4l2loopback video_nr=2 card_label=\"OBS Virtual Camera\" && pamixer --default-source --set-volume 70 && obs" // fixed with nixos
alias video_cut="video-cut"
alias ss="sudo systemctl"
alias cl="wl-copy"
alias wl_copy="wl-copy"
alias gz="tar -xvzf -C"
alias tokej="tokei -o json | jq . > /tmp/tokei.json"
alias book="booktyping run --myopia"
alias tokio-console="tokio-console --lang en_US.UTF-8"
alias tokio_console="tokio-console"
alias fm="yazi" # File manager
alias t="eza -snew -r | head -n 1"
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
alias cdd="cd .. && cd -" # effectively just reloads `direnv`
alias monkey="smassh"
alias bbeats="sudo -Es nice -n -20 /etc/profiles/per-user/v/bin/bbeats" # otherwise any demanding process will produce bad breaks in sound

# # fish
function where
	set details (functions --details $argv[1])
	if test "$details" = "-" # can't locate aliases (2024/10/29)
		rg -H "alias $argv[1]" "$NIXOS_CONFIG/home/config/fish"
	else
		echo $details
	end
	type $argv[1]
end
alias sr="source $NIXOS_CONFIG/home/config/fish/mod.fish" # Fish equivalent for reloading configuration.
#

# # nix
alias flake-build="sudo nixos-rebuild switch --flake .#myhost --show-trace -L -v"
#TODO!: make into a function and git-commit with $argv concatenation for message
alias nixup="git -C '$NIXOS_CONFIG' add -A && nix flake update --flake '$NIXOS_CONFIG' && sudo nixos-rebuild switch --show-trace -v --impure --fast && git_upload '$NIXOS_CONFIG'"
#TODO!: add git wrapper
alias nhup="nh os switch --hostname vlaptop '$NIXOS_CONFIG' -- --impure"
alias nshell="nix-shell --command fish"
alias ndevelop="nix develop --command fish"
#alias nupdate="nix flake lock --update-input nixpkgs --update-input"
alias nup="nix flake update"
alias up="$NIXOS_CONFIG/home/scripts/maintenance/main.sh"
alias nb="sudo nixos-rebuild switch --impure --fast --flake ~/nix#$(hostname) && beep 'nix rb 0' || beep 'nix rb 1'" #TODO: add some git add -A on $NIXOS_CONFIG and maybe make this into the main way of running this
function nbg
	set hostName (hostname)
	if [ (count $argv) = 1 ]
		set hostName $argv[1]
	end
	sudo nixos-rebuild switch --flake "github:valeratrades/nix#$hostName" --impure --fast
end
#

# # direnv
alias dira="git add -A && direnv allow"
function de
	# direnv wrap
	direnv allow && \
	$argv && \
	direnv deny
end
#

# # exa (for future reference only, as now I have programs.eza.enable in home.nix)
#alias ll="exa -lA"
#

# # auth
function 2fa
	if [ (count $argv) != 1 ] && [ (count $argv) != 2 ]
		echo "Usage: 2fa <app_name> [base]"
		return
	end

	set pass_var (string upper "$argv[1]")_TOTP
	if set 2fa_pass (eval echo $$pass_var)
		:
	else
		echo "Variable $pass_var is not set."
		return 1
	end

	set base 6
	if [ (count $argv) = 2 ]
		set base $argv[2]
	end

	oathtool --base32 --totp "$2fa_pass" -d $base
end
function 2fac
	set r (2fa $argv)
	echo $r | wl-copy
	echo """$r
Copied to clipboard."""
end
#


#gpg id = gpg --list-keys --with-colons | awk -F: '/uid/ && /valeratrades@gmail.com/ {getline; print $5}'

# # keyd
alias rkeyd="sudo keyd reload && sudo journalctl -eu keyd"
alias lkeyd="sudo keyd -m"
#

# # lean
function lr
	#TODO!: inference of binary name
	lake build && printf '\n' && .lake/build/bin/$argv[1]
end
#

# # spotify
# name is play of words on russian; can't use `spotify` because of occuring recursion
alias spoy="set -x LD_PRELOAD $SPOTIFY_ADBLOCK_LIB; spotify" # the SPOTIFY_ADBLOCK_LIB is set by nixos config
#


# # Starship
#starship init fish | source # the .enable in configuration.nix is apparently insufficient for the shells that are spawned by tmux
#
