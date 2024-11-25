# Installation
Before building, from the directory to which it is cloned:
```sh
sudo mkdir -p /usr/share/X11/xkb/symbols && sudo cp -r ./home/config/xkb_symbols/* /usr/share/X11/xkb/symbols/
```

# Reqs
~/s/g/private/credentials.fish file with following variables set:
```fish
$GITHUB_KEY
```

# Manual adjustments
git config in ./os/configuration.nix must be adjusted for the correct username and email
